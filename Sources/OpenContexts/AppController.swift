import AppKit
import Combine
import OpenContextsCore
import Sparkle
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let settingsWindowID = "local:settings"
    private let windowService = WindowService()
    private let groupStore = GroupStore()
    private let shortcuts = ShortcutController()
    private let settings = AppSettings()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    private var sidebars: [CGDirectDisplayID: SidebarPanel] = [:]
    private var switchers: [CGDirectDisplayID: SwitcherPanel] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    private var switchingResults: [WindowSearch.Match] = []
    private var switchingWindowCount = 0
    private var switchingGroupID: String?
    private var switchingGroupIDs: [String: String] = [:]
    private var switchingGroupCounts: [String: Int] = [:]
    private var searchQuery = ""
    private var selectionBeforeSearch: String?
    private var selectedIndex = 0
    private var currentAppOnly: Bool?
    private var currentAppPID: pid_t?
    private var didRestoreGroups = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenuBar()
        configureShortcuts()
        observeState()
        rebuildPanels()
        windowService.setIncludeAllSpaces(settings.showWindowsFromAllDesktops)
        windowService.start()
        if !windowService.hasAccessibility { showSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcuts.stop()
        windowService.stop()
        sidebars.values.forEach { $0.close() }
        switchers.values.forEach { $0.close() }
    }

    private func configureShortcuts() {
        shortcuts.configure(allWindows: settings.allWindowsShortcut, currentApp: settings.currentAppShortcut,
                            sidebar: settings.sidebarShortcut, groupMode: settings.groupModeShortcut,
                            switcherGroupsEnabled: settings.switcherGroupsEnabled)
        shortcuts.canBegin = { [weak self] currentAppOnly in
            self?.availableWindows(currentAppOnly: currentAppOnly).isEmpty == false
        }
        shortcuts.onAction = { [weak self] action in self?.handle(action) }
        shortcuts.canDismissSidebar = { [weak self] in
            self?.sidebars.values.contains(where: { $0.canDismissShortcut }) == true
        }
    }

    private func observeState() {
        windowService.$windows.sink { [weak self] windows in
            guard let self else { return }
            if self.windowService.hasCompletedInitialScan && !self.didRestoreGroups {
                self.didRestoreGroups = true
                self.groupStore.reconcile(windows)
            } else {
                self.groupStore.updateLiveWindows(windows)
            }
            DispatchQueue.main.async { [weak self] in
                self?.updateSidebars()
                self?.refreshVisibleSwitcher()
            }
        }.store(in: &cancellables)

        windowService.$fullscreenScreenIDs.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateSidebars() }
        }
            .store(in: &cancellables)

        windowService.$appBadges.removeDuplicates().sink { [weak self] badges in
            self?.sidebars.values.forEach { $0.updateBadges(badges) }
        }.store(in: &cancellables)

        windowService.$focusedWindowID.removeDuplicates().sink { [weak self] id in
            self?.sidebars.values.forEach { $0.updateFocusedWindow(id) }
        }.store(in: &cancellables)

        windowService.$hasAccessibility.removeDuplicates().sink { [weak self] trusted in
            guard let self else { return }
            if trusted { _ = self.shortcuts.start() } else { self.shortcuts.stop() }
        }.store(in: &cancellables)

        groupStore.$revision.dropFirst().sink { [weak self] _ in
            self?.updateSidebars()
            self?.refreshVisibleSwitcher()
        }
            .store(in: &cancellables)

        // objectWillChange fires before the new value is stored, so read settings on the next turn.
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateSidebars()
                self?.configureMenuBar()
                if let self {
                    self.shortcuts.configure(allWindows: self.settings.allWindowsShortcut,
                                             currentApp: self.settings.currentAppShortcut,
                                             sidebar: self.settings.sidebarShortcut,
                                             groupMode: self.settings.groupModeShortcut,
                                             switcherGroupsEnabled: self.settings.switcherGroupsEnabled)
                    self.windowService.setIncludeAllSpaces(self.settings.showWindowsFromAllDesktops)
                    if self.settings.sidebarShortcut == nil { self.dismissSidebar() }
                    self.settingsWindow?.title = L10n.text("OpenContexts Settings", language: self.settings.language)
                    if self.currentAppOnly != nil { self.refreshVisibleSwitcher() }
                }
            }
        }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.rebuildPanels() }
            .store(in: &cancellables)
    }

    private func rebuildPanels() {
        sidebars.values.forEach { $0.close() }
        switchers.values.forEach { $0.close() }
        sidebars = [:]
        switchers = [:]

        for screen in NSScreen.screens {
            let id = Self.displayID(for: screen)
            sidebars[id] = SidebarPanel(
                screen: screen,
                onActivate: { [weak self] in self?.windowService.activate($0) },
                canCloseWindow: { [weak self] in self?.windowService.canClose($0) ?? false },
                onCloseWindow: { [weak self] in self?.windowService.close($0) },
                windowPinPosition: { [weak self] in self?.groupStore.pinPosition(id: $0) },
                onTogglePin: { [weak self] in self?.groupStore.togglePin(id: $0) },
                onMoveWindow: { [weak self] id, groupID, beforeID, order in
                    self?.groupStore.moveWindow(id: id, to: groupID, before: beforeID,
                                                visibleOrderByGroup: order)
                },
                onMoveGroup: { [weak self] id, beforeID in
                    self?.groupStore.moveGroup(id: id, before: beforeID)
                },
                onCreateGroup: { [weak self] in self?.groupStore.createGroup(name: $0) },
                onRenameGroup: { [weak self] id, name in self?.groupStore.renameGroup(id: id, name: name) },
                onDeleteGroup: { [weak self] in self?.groupStore.deleteGroup(id: $0) }
            )
            switchers[id] = SwitcherPanel(
                screen: screen,
                onActivate: { [weak self] id in self?.finishSwitcher(activating: id) },
                onSelect: { [weak self] id in self?.selectSwitcherWindow(id: id) },
                onSelectGroup: { [weak self] id in self?.changeSwitcherGroup(to: id) },
                onToggleGroups: { [weak self] in self?.toggleSwitcherGroups() }
            )
        }
        updateSidebars()
        if currentAppOnly != nil {
            showSwitchers()
        }
    }

    private func updateSidebars() {
        let windowsByGroup = Dictionary(uniqueKeysWithValues: groupStore.groups.map {
            ($0.id, groupStore.windows(in: $0.id).filter(\.isOnCurrentSpace))
        })
        for (id, panel) in sidebars {
            panel.update(
                groups: groupStore.groups,
                windowsByGroup: windowsByGroup,
                alwaysVisible: settings.sidebarMode == .always,
                fullscreen: windowService.fullscreenScreenIDs.contains(id),
                enabled: settings.sidebarMode != .hidden,
                showUngrouped: settings.showUngrouped,
                showCreateGroup: settings.showCreateGroup,
                verticalAlignment: settings.sidebarVerticalAlignment,
                sidebarWidth: CGFloat(settings.sidebarWidth),
                position: settings.sidebarPosition,
                itemDisplayMode: settings.sidebarItemDisplayMode,
                language: settings.language
            )
            panel.updateBadges(windowService.appBadges)
            panel.updateFocusedWindow(windowService.focusedWindowID)
        }
    }

    private func availableWindows(currentAppOnly: Bool, pid: pid_t? = nil) -> [WindowInfo] {
        let windows = windowService.windows.filter { settings.showWindowsFromAllDesktops || $0.isOnCurrentSpace }
        guard currentAppOnly else { return windows }
        let processID = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        return windows.filter { $0.processID == processID }
    }

    private var selectedWindowID: String? {
        switchingResults.indices.contains(selectedIndex) ? switchingResults[selectedIndex].window.id : nil
    }

    private func switcherWindows(currentAppOnly: Bool) -> [WindowInfo] {
        let windows = availableWindows(currentAppOnly: currentAppOnly, pid: currentAppPID)
        guard settings.switcherGroupsEnabled else {
            switchingGroupID = nil
            switchingGroupIDs = [:]
            switchingGroupCounts = [:]
            return windows
        }
        let assignedGroups = groupStore.groupIDsByWindowID
        switchingGroupIDs = Dictionary(uniqueKeysWithValues: windows.map {
            ($0.id, assignedGroups[$0.id] ?? GroupStore.ungroupedID)
        })
        switchingGroupCounts = switchingGroupIDs.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return windows
    }

    private func filterSwitcherWindows(_ windows: [WindowInfo]) {
        let scopedWindows = switchingGroupID.map { groupID in
            windows.filter { switchingGroupIDs[$0.id] == groupID }
        } ?? windows
        switchingWindowCount = scopedWindows.count
        switchingResults = WindowSwitcher.filter(scopedWindows, query: searchQuery,
                                                 allSpaces: settings.showWindowsFromAllDesktops)
    }

    private var availableSwitcherGroupIDs: [String] {
        groupStore.groups.map(\.id).filter { switchingGroupCounts[$0, default: 0] > 0 }
    }

    private func toggleSwitcherGroups() {
        if switchingGroupID != nil {
            changeSwitcherGroup(to: nil)
        } else if let groupID = selectedWindowID.flatMap({ switchingGroupIDs[$0] })
                    ?? windowService.focusedWindowID.flatMap({ switchingGroupIDs[$0] })
                    ?? availableSwitcherGroupIDs.first {
            changeSwitcherGroup(to: groupID)
        }
    }

    private func changeSwitcherGroup(to groupID: String?) {
        guard settings.switcherGroupsEnabled, currentAppOnly != nil, groupID != switchingGroupID else { return }
        if let groupID, switchingGroupCounts[groupID, default: 0] == 0 { return }
        switchingGroupID = groupID
        if let groupID, let beforeSearch = selectionBeforeSearch, switchingGroupIDs[beforeSearch] != groupID {
            selectionBeforeSearch = nil
        }
        refreshVisibleSwitcher(resetHover: true)
    }

    private func handle(_ action: SwitcherAction) {
        windowService.cancelActivation()
        switch action {
        case .toggleSidebar:
            finishSwitcher(activating: nil)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                    ?? NSScreen.main,
                  let panel = sidebars[Self.displayID(for: screen)] else { return }
            let expanded = !panel.isShortcutExpanded
            dismissSidebar()
            panel.setShortcutExpanded(expanded)
        case .dismissSidebar:
            dismissSidebar()
        case let .begin(currentAppOnly, reverse):
            dismissSidebar()
            searchQuery = ""
            selectionBeforeSearch = nil
            self.currentAppOnly = currentAppOnly
            currentAppPID = currentAppOnly ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
            let windows = switcherWindows(currentAppOnly: currentAppOnly)
            guard !windows.isEmpty else { finishSwitcher(activating: nil); return }
            switchingGroupID = settings.switcherGroupsEnabled && settings.startsInGroupMode
                ? windowService.focusedWindowID.flatMap { switchingGroupIDs[$0] }
                    ?? windows.first.flatMap { switchingGroupIDs[$0.id] }
                : nil
            filterSwitcherWindows(windows)
            let firstIsFocused = switchingResults.first?.window.id == windowService.focusedWindowID
            selectedIndex = reverse ? switchingResults.count - 1
                : firstIsFocused ? min(1, switchingResults.count - 1) : 0
            showSwitchers()
        case let .step(amount):
            guard !switchingResults.isEmpty else { return }
            selectedIndex = (selectedIndex + amount % switchingResults.count + switchingResults.count)
                % switchingResults.count
            updateSwitchers(resetHover: true)
        case let .groupArrow(direction, shifted):
            if let switchingGroupID {
                if shifted {
                    if settings.groupModeShortcut == nil { changeSwitcherGroup(to: nil) }
                } else {
                    let groups = availableSwitcherGroupIDs
                    guard !groups.isEmpty else { return }
                    let index = groups.firstIndex(of: switchingGroupID).map {
                        ($0 + direction + groups.count) % groups.count
                    } ?? (direction < 0 ? groups.count - 1 : 0)
                    changeSwitcherGroup(to: groups[index])
                }
            } else if !shifted, settings.groupModeShortcut == nil {
                toggleSwitcherGroups()
            }
        case .toggleGroups:
            toggleSwitcherGroups()
        case let .search(query):
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let currentAppOnly else { return }
            if searchQuery.isEmpty {
                selectionBeforeSearch = selectedWindowID
            }
            searchQuery = query
            let windows = switcherWindows(currentAppOnly: currentAppOnly)
            guard !windows.isEmpty else { finishSwitcher(activating: nil); return }
            filterSwitcherWindows(windows)
            selectedIndex = query.isEmpty
                ? selectionBeforeSearch.flatMap { id in switchingResults.firstIndex { $0.window.id == id } } ?? 0
                : 0
            updateSwitchers(resetHover: true)
        case .commit:
            finishSwitcher(activating: selectedWindowID)
        case .cancel:
            finishSwitcher(activating: nil)
        }
    }

    private func refreshVisibleSwitcher(resetHover: Bool = false) {
        guard let currentAppOnly else { return }
        let selectedID = selectedWindowID
        let windows = switcherWindows(currentAppOnly: currentAppOnly)
        guard !windows.isEmpty else {
            finishSwitcher(activating: nil)
            return
        }
        filterSwitcherWindows(windows)
        selectedIndex = selectedID.flatMap { id in switchingResults.firstIndex(where: { $0.window.id == id }) }
            ?? (resetHover ? 0 : min(selectedIndex, max(0, switchingResults.count - 1)))
        updateSwitchers(resetHover: resetHover)
    }

    private func dismissSidebar() {
        sidebars.values.filter { $0.isShortcutExpanded }.forEach { $0.setShortcutExpanded(false) }
    }

    private func selectSwitcherWindow(id: String) {
        guard currentAppOnly != nil,
              let index = switchingResults.firstIndex(where: { $0.window.id == id }),
              index != selectedIndex else { return }
        selectedIndex = index
        updateSwitchers()
    }

    private func updateSwitchers(resetHover: Bool = false) {
        let scope: SwitcherPanel.GroupScope?
        if settings.switcherGroupsEnabled {
            let groups = groupStore.groups.filter {
                $0.id != GroupStore.ungroupedID || switchingGroupCounts[$0.id, default: 0] > 0
                    || switchingGroupID == $0.id
            }
            let names = Dictionary(uniqueKeysWithValues: groups.filter { $0.id != GroupStore.ungroupedID }
                .map { ($0.id, $0.name) })
            scope = SwitcherPanel.GroupScope(
                selectedID: switchingGroupID,
                tabs: groups.map { SwitcherPanel.GroupTab(group: $0, count: switchingGroupCounts[$0.id, default: 0]) },
                windowGroupNames: switchingGroupIDs.compactMapValues { names[$0] },
                shortcut: settings.groupModeShortcut?.display
            )
        } else {
            scope = nil
        }
        switchers.values.forEach {
            $0.update(results: switchingResults, selectedIndex: selectedIndex, resetHover: resetHover,
                      groupBySpace: settings.showWindowsFromAllDesktops,
                      query: searchQuery, totalWindowCount: switchingWindowCount, language: settings.language,
                      scope: scope)
        }
    }

    private func showSwitchers() {
        updateSwitchers(resetHover: true)
        switchers.values.forEach { $0.present() }
    }

    private func finishSwitcher(activating id: String?) {
        shortcuts.resetState()
        switchers.values.forEach { $0.hideSwitcher() }
        switchingResults = []
        switchingWindowCount = 0
        switchingGroupID = nil
        switchingGroupIDs = [:]
        switchingGroupCounts = [:]
        searchQuery = ""
        selectionBeforeSearch = nil
        selectedIndex = 0
        currentAppOnly = nil
        currentAppPID = nil
        if let id { windowService.activate(id) }
    }

    private func configureMenuBar() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "OpenContexts")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.setAccessibilityLabel("OpenContexts")
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text("Settings…", language: settings.language), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L10n.text("Check for Updates…", language: settings.language), action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            .target = updaterController
        menu.addItem(withTitle: L10n.text("Grant Accessibility Access…", language: settings.language), action: #selector(requestAccessibility), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("Quit OpenContexts", language: settings.language), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(
                settings: settings,
                windowService: windowService,
                groupStore: groupStore,
                shortcuts: shortcuts
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = L10n.text("OpenContexts Settings", language: settings.language)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        if let settingsWindow {
            windowService.registerLocalWindow(settingsWindow, id: Self.settingsWindowID)
        }
    }

    @objc private func requestAccessibility() {
        windowService.requestAccessibility()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        shortcuts.cancelRecording()
        windowService.unregisterLocalWindow(id: Self.settingsWindowID)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        shortcuts.cancelRecording()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        windowService.registerLocalWindow(window, id: Self.settingsWindowID)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
