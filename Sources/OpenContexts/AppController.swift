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
        shortcuts.configure(allWindows: settings.allWindowsShortcut, currentApp: settings.currentAppShortcut)
        shortcuts.canBegin = { [weak self] currentAppOnly in
            self?.availableWindows(currentAppOnly: currentAppOnly).isEmpty == false
        }
        shortcuts.onAction = { [weak self] action in self?.handle(action) }
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

        windowService.$hasAccessibility.removeDuplicates().sink { [weak self] trusted in
            guard let self else { return }
            if trusted { _ = self.shortcuts.start() } else { self.shortcuts.stop() }
        }.store(in: &cancellables)

        groupStore.$revision.dropFirst().sink { [weak self] _ in self?.updateSidebars() }
            .store(in: &cancellables)

        // objectWillChange fires before the new value is stored, so read settings on the next turn.
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateSidebars()
                self?.configureMenuBar()
                if let self {
                    self.shortcuts.configure(allWindows: self.settings.allWindowsShortcut,
                                             currentApp: self.settings.currentAppShortcut)
                    self.settingsWindow?.title = L10n.text("OpenContexts Settings", language: self.settings.language)
                    if self.currentAppOnly != nil { self.updateSwitchers() }
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
                onSelect: { [weak self] id in self?.selectSwitcherWindow(id: id) }
            )
        }
        updateSidebars()
        if currentAppOnly != nil {
            switchers.values.forEach {
                $0.show(results: switchingResults, selectedIndex: selectedIndex, query: searchQuery,
                        totalWindowCount: switchingWindowCount, language: settings.language)
            }
        }
    }

    private func updateSidebars() {
        let windowsByGroup = Dictionary(uniqueKeysWithValues: groupStore.groups.map {
            ($0.id, groupStore.windows(in: $0.id))
        })
        for (id, panel) in sidebars {
            panel.update(
                groups: groupStore.groups,
                windowsByGroup: windowsByGroup,
                alwaysVisible: settings.sidebarMode == .always,
                fullscreen: windowService.fullscreenScreenIDs.contains(id),
                position: settings.sidebarPosition,
                itemDisplayMode: settings.sidebarItemDisplayMode,
                language: settings.language
            )
            panel.updateBadges(windowService.appBadges)
        }
    }

    private func availableWindows(currentAppOnly: Bool, pid: pid_t? = nil) -> [WindowInfo] {
        guard currentAppOnly else { return windowService.windows }
        let processID = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        return windowService.windows.filter { $0.processID == processID }
    }

    private func handle(_ action: SwitcherAction) {
        switch action {
        case let .begin(currentAppOnly, reverse):
            searchQuery = ""
            selectionBeforeSearch = nil
            self.currentAppOnly = currentAppOnly
            currentAppPID = currentAppOnly ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
            switchingResults = WindowSearch.filter(availableWindows(currentAppOnly: currentAppOnly, pid: currentAppPID),
                                                    query: "")
            switchingWindowCount = switchingResults.count
            guard !switchingResults.isEmpty else { return }
            selectedIndex = reverse ? switchingResults.count - 1 : min(1, switchingResults.count - 1)
            switchers.values.forEach {
                $0.show(results: switchingResults, selectedIndex: selectedIndex,
                        totalWindowCount: switchingWindowCount, language: settings.language)
            }
        case let .step(amount):
            guard !switchingResults.isEmpty else { return }
            selectedIndex = (selectedIndex + amount % switchingResults.count + switchingResults.count)
                % switchingResults.count
            updateSwitchers(resetHover: true)
        case let .search(query):
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let currentAppOnly else { return }
            if searchQuery.isEmpty {
                selectionBeforeSearch = switchingResults.indices.contains(selectedIndex)
                    ? switchingResults[selectedIndex].window.id : nil
            }
            searchQuery = query
            let windows = availableWindows(currentAppOnly: currentAppOnly, pid: currentAppPID)
            switchingWindowCount = windows.count
            guard !windows.isEmpty else { finishSwitcher(activating: nil); return }
            switchingResults = WindowSearch.filter(windows, query: query)
            selectedIndex = query.isEmpty
                ? selectionBeforeSearch.flatMap { id in switchingResults.firstIndex { $0.window.id == id } } ?? 0
                : 0
            updateSwitchers(resetHover: true)
        case .commit:
            let id = switchingResults.indices.contains(selectedIndex) ? switchingResults[selectedIndex].window.id : nil
            finishSwitcher(activating: id)
        case .cancel:
            finishSwitcher(activating: nil)
        }
    }

    private func refreshVisibleSwitcher() {
        guard let currentAppOnly else { return }
        let selectedID = switchingResults.indices.contains(selectedIndex) ? switchingResults[selectedIndex].window.id : nil
        let windows = availableWindows(currentAppOnly: currentAppOnly, pid: currentAppPID)
        switchingWindowCount = windows.count
        guard !windows.isEmpty else {
            finishSwitcher(activating: nil)
            return
        }
        switchingResults = WindowSearch.filter(windows, query: searchQuery)
        selectedIndex = selectedID.flatMap { id in switchingResults.firstIndex(where: { $0.window.id == id }) }
            ?? min(selectedIndex, max(0, switchingResults.count - 1))
        updateSwitchers()
    }

    private func selectSwitcherWindow(id: String) {
        guard currentAppOnly != nil,
              let index = switchingResults.firstIndex(where: { $0.window.id == id }),
              index != selectedIndex else { return }
        selectedIndex = index
        updateSwitchers()
    }

    private func updateSwitchers(resetHover: Bool = false) {
        switchers.values.forEach {
            $0.update(results: switchingResults, selectedIndex: selectedIndex, resetHover: resetHover,
                      query: searchQuery, totalWindowCount: switchingWindowCount, language: settings.language)
        }
    }

    private func finishSwitcher(activating id: String?) {
        shortcuts.resetState()
        switchers.values.forEach { $0.hideSwitcher() }
        switchingResults = []
        switchingWindowCount = 0
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
