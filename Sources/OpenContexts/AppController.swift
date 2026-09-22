import AppKit
import Combine
import OpenContextsCore
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let settingsWindowID = "local:settings"
    private let windowService = WindowService()
    private let groupStore = GroupStore()
    private let shortcuts = ShortcutController()
    private let settings = AppSettings()

    private var sidebars: [CGDirectDisplayID: SidebarPanel] = [:]
    private var switchers: [CGDirectDisplayID: SwitcherPanel] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    private var switchingWindows: [WindowInfo] = []
    private var selectedIndex = 0
    private var currentAppOnly: Bool?
    private var currentAppPID: pid_t?

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
        shortcuts.canBegin = { [weak self] currentAppOnly in
            self?.availableWindows(currentAppOnly: currentAppOnly).isEmpty == false
        }
        shortcuts.onAction = { [weak self] action in self?.handle(action) }
    }

    private func observeState() {
        windowService.$windows.sink { [weak self] windows in
            guard let self else { return }
            self.groupStore.reconcile(windows)
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

        settings.$sidebarMode.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateSidebars() }
        }
            .store(in: &cancellables)
        settings.$sidebarPosition.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateSidebars() }
        }
            .store(in: &cancellables)
        settings.$sidebarItemDisplayMode.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateSidebars() }
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
                onMoveWindow: { [weak self] id, groupID, beforeID in
                    self?.groupStore.moveWindow(id: id, to: groupID, before: beforeID)
                },
                onMoveGroup: { [weak self] id, beforeID in
                    self?.groupStore.moveGroup(id: id, before: beforeID)
                },
                onCreateGroup: { [weak self] in self?.groupStore.createGroup(name: $0) },
                onRenameGroup: { [weak self] id, name in self?.groupStore.renameGroup(id: id, name: name) },
                onDeleteGroup: { [weak self] in self?.groupStore.deleteGroup(id: $0) }
            )
            switchers[id] = SwitcherPanel(screen: screen) { [weak self] id in
                self?.finishSwitcher(activating: id)
            }
        }
        updateSidebars()
        if currentAppOnly != nil, !switchingWindows.isEmpty {
            switchers.values.forEach { $0.show(windows: switchingWindows, selectedIndex: selectedIndex) }
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
                itemDisplayMode: settings.sidebarItemDisplayMode
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
            self.currentAppOnly = currentAppOnly
            currentAppPID = currentAppOnly ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
            switchingWindows = availableWindows(currentAppOnly: currentAppOnly, pid: currentAppPID)
            guard !switchingWindows.isEmpty else { return }
            selectedIndex = reverse ? switchingWindows.count - 1 : min(1, switchingWindows.count - 1)
            switchers.values.forEach { $0.show(windows: switchingWindows, selectedIndex: selectedIndex) }
        case let .step(amount):
            guard !switchingWindows.isEmpty else { return }
            selectedIndex = (selectedIndex + amount % switchingWindows.count + switchingWindows.count)
                % switchingWindows.count
            switchers.values.forEach { $0.update(windows: switchingWindows, selectedIndex: selectedIndex) }
        case .commit:
            let id = switchingWindows.indices.contains(selectedIndex) ? switchingWindows[selectedIndex].id : nil
            finishSwitcher(activating: id)
        case .cancel:
            finishSwitcher(activating: nil)
        }
    }

    private func refreshVisibleSwitcher() {
        guard let currentAppOnly else { return }
        let selectedID = switchingWindows.indices.contains(selectedIndex) ? switchingWindows[selectedIndex].id : nil
        switchingWindows = availableWindows(currentAppOnly: currentAppOnly, pid: currentAppPID)
        guard !switchingWindows.isEmpty else {
            finishSwitcher(activating: nil)
            return
        }
        selectedIndex = selectedID.flatMap { id in switchingWindows.firstIndex(where: { $0.id == id }) }
            ?? min(selectedIndex, switchingWindows.count - 1)
        switchers.values.forEach { $0.update(windows: switchingWindows, selectedIndex: selectedIndex) }
    }

    private func finishSwitcher(activating id: String?) {
        shortcuts.resetState()
        switchers.values.forEach { $0.hideSwitcher() }
        switchingWindows = []
        selectedIndex = 0
        currentAppOnly = nil
        currentAppPID = nil
        if let id { windowService.activate(id) }
    }

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "OpenContexts")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.setAccessibilityLabel("OpenContexts")
        let menu = NSMenu()
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "授予辅助功能权限…", action: #selector(requestAccessibility), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 OpenContexts", action: #selector(quit), keyEquivalent: "q").target = self
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
            window.title = "OpenContexts 设置"
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
        windowService.unregisterLocalWindow(id: Self.settingsWindowID)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        windowService.registerLocalWindow(window, id: Self.settingsWindowID)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
