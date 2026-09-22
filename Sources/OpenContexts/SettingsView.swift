import AppKit
import OpenContextsCore
import SwiftUI

enum SidebarVisibilityMode: String, CaseIterable, Identifiable {
    case always
    case hover

    var id: String { rawValue }
    var title: String { self == .always ? "始终显示" : "悬浮显示" }
}

enum SidebarPosition: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: "左"
        case .right: "右"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var sidebarMode: SidebarVisibilityMode
    @Published private(set) var sidebarPosition: SidebarPosition

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sidebarMode = SidebarVisibilityMode(rawValue: defaults.string(forKey: "sidebarMode") ?? "") ?? .always
        let savedPosition = defaults.string(forKey: "sidebarPosition")
        if let savedPosition, let position = SidebarPosition(rawValue: savedPosition) {
            sidebarPosition = position
        } else {
            sidebarPosition = .right
            if savedPosition != nil { defaults.set(SidebarPosition.right.rawValue, forKey: "sidebarPosition") }
        }
    }

    func setSidebarMode(_ mode: SidebarVisibilityMode) {
        sidebarMode = mode
        defaults.set(mode.rawValue, forKey: "sidebarMode")
    }

    func setSidebarPosition(_ position: SidebarPosition) {
        sidebarPosition = position
        defaults.set(position.rawValue, forKey: "sidebarPosition")
    }

    static func selfCheck() -> Bool {
        let suite = "OpenContexts.self-check.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return false }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(16, forKey: "allWindowsKeyCode")
        defaults.set(17, forKey: "currentAppKeyCode")
        defaults.set("top", forKey: "sidebarPosition")
        let migratedTop = AppSettings(defaults: defaults)
        guard migratedTop.sidebarPosition == .right,
              defaults.string(forKey: "sidebarPosition") == SidebarPosition.right.rawValue else { return false }
        defaults.set("bottom", forKey: "sidebarPosition")
        let migratedBottom = AppSettings(defaults: defaults)
        guard migratedBottom.sidebarPosition == .right,
              defaults.string(forKey: "sidebarPosition") == SidebarPosition.right.rawValue else { return false }
        defaults.set("left", forKey: "sidebarPosition")
        let settings = AppSettings(defaults: defaults)
        return ShortcutController.allWindowsKeyCode == 48
            && ShortcutController.currentAppKeyCode == 50
            && settings.sidebarPosition == .left
            && defaults.string(forKey: "sidebarPosition") == SidebarPosition.left.rawValue
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var windowService: WindowService
    @ObservedObject var groupStore: GroupStore
    @ObservedObject var shortcuts: ShortcutController

    var body: some View {
        Form {
            Picker("侧栏", selection: Binding(
                get: { settings.sidebarMode },
                set: settings.setSidebarMode
            )) {
                ForEach(SidebarVisibilityMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("侧栏位置", selection: Binding(
                get: { settings.sidebarPosition },
                set: settings.setSidebarPosition
            )) {
                ForEach(SidebarPosition.allCases) { position in
                    Text(position.title).tag(position)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("所有窗口") {
                Text("⌘Tab")
            }
            LabeledContent("当前应用窗口") {
                Text("⌘`")
            }

            LabeledContent("辅助功能") {
                HStack {
                    Text(windowService.hasAccessibility ? "已授权" : "未授权")
                    if !windowService.hasAccessibility {
                        Button("请求授权") { windowService.requestAccessibility() }
                    }
                }
            }
            LabeledContent("全局快捷键") {
                HStack {
                    Text(shortcuts.isRunning ? "运行中" : "未运行")
                    if windowService.hasAccessibility && !shortcuts.isRunning {
                        Button("重试") { _ = shortcuts.start() }
                    }
                }
            }
            if let error = groupStore.persistenceError {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 340)
    }
}
