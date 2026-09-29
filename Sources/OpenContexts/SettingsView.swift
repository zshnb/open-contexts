import AppKit
import OpenContextsCore
import SwiftUI

enum SidebarVisibilityMode: String, CaseIterable, Identifiable {
    case always
    case hover

    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        L10n.text(self == .always ? "Always visible" : "Show on hover", language: language)
    }
}

enum SidebarPosition: String, CaseIterable, Identifiable {
    case left
    case right
    case bottom

    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .left: L10n.text("Left", language: language)
        case .right: L10n.text("Right", language: language)
        case .bottom: L10n.text("Bottom", language: language)
        }
    }
}

enum SidebarItemDisplayMode: String, CaseIterable, Identifiable {
    case icon
    case iconAndTitle

    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        L10n.text(self == .icon ? "Icons only" : "Icons and titles", language: language)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var sidebarMode: SidebarVisibilityMode
    @Published private(set) var sidebarPosition: SidebarPosition
    @Published private(set) var sidebarItemDisplayMode: SidebarItemDisplayMode
    @Published private(set) var language: AppLanguage

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        sidebarMode = SidebarVisibilityMode(rawValue: defaults.string(forKey: "sidebarMode") ?? "") ?? .always
        sidebarItemDisplayMode = SidebarItemDisplayMode(
            rawValue: defaults.string(forKey: "sidebarItemDisplayMode") ?? ""
        ) ?? .iconAndTitle
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

    func setSidebarItemDisplayMode(_ mode: SidebarItemDisplayMode) {
        sidebarItemDisplayMode = mode
        defaults.set(mode.rawValue, forKey: "sidebarItemDisplayMode")
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: "language")
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
        defaults.set("icon", forKey: "sidebarItemDisplayMode")
        let bottom = AppSettings(defaults: defaults)
        guard bottom.sidebarPosition == .bottom,
              bottom.sidebarItemDisplayMode == .icon,
              defaults.string(forKey: "sidebarPosition") == SidebarPosition.bottom.rawValue else { return false }
        defaults.set("left", forKey: "sidebarPosition")
        let settings = AppSettings(defaults: defaults)
        settings.setLanguage(.ja)
        guard AppSettings(defaults: defaults).language == .ja,
              defaults.string(forKey: "language") == "ja" else { return false }
        defaults.set("unsupported", forKey: "language")
        guard AppSettings(defaults: defaults).language == .system else { return false }
        return ShortcutController.allWindowsKeyCode == 48
            && ShortcutController.currentAppKeyCode == 50
            && settings.sidebarPosition == .left
            && settings.sidebarItemDisplayMode == .icon
            && defaults.string(forKey: "sidebarPosition") == SidebarPosition.left.rawValue
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var windowService: WindowService
    @ObservedObject var groupStore: GroupStore
    @ObservedObject var shortcuts: ShortcutController

    var body: some View {
        let language = settings.language
        Form {
            Picker(L10n.text("Sidebar", language: language), selection: Binding(
                get: { settings.sidebarMode },
                set: settings.setSidebarMode
            )) {
                ForEach(SidebarVisibilityMode.allCases) { mode in
                    Text(mode.title(language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker(L10n.text("Display", language: language), selection: Binding(
                get: { settings.sidebarItemDisplayMode },
                set: settings.setSidebarItemDisplayMode
            )) {
                ForEach(SidebarItemDisplayMode.allCases) { mode in
                    Text(mode.title(language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker(L10n.text("Sidebar position", language: language), selection: Binding(
                get: { settings.sidebarPosition },
                set: settings.setSidebarPosition
            )) {
                ForEach(SidebarPosition.allCases) { position in
                    Text(position.title(language)).tag(position)
                }
            }
            .pickerStyle(.segmented)

            Picker(L10n.text("Language", language: language), selection: Binding(
                get: { settings.language },
                set: settings.setLanguage
            )) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option == .system ? L10n.text("System", language: language) : option.name).tag(option)
                }
            }

            LabeledContent(L10n.text("All windows", language: language)) {
                Text("⌘Tab")
            }
            LabeledContent(L10n.text("Current app windows", language: language)) {
                Text("⌘`")
            }

            LabeledContent(L10n.text("Accessibility", language: language)) {
                HStack {
                    Text(L10n.text(windowService.hasAccessibility ? "Granted" : "Not granted", language: language))
                    if !windowService.hasAccessibility {
                        Button(L10n.text("Request access", language: language)) { windowService.requestAccessibility() }
                    }
                }
            }
            LabeledContent(L10n.text("Global shortcuts", language: language)) {
                HStack {
                    Text(L10n.text(shortcuts.isRunning ? "Running" : "Not running", language: language))
                    if windowService.hasAccessibility && !shortcuts.isRunning {
                        Button(L10n.text("Retry", language: language)) { _ = shortcuts.start() }
                    }
                }
            }
            if let detail = groupStore.persistenceErrorDetail,
               let operation = groupStore.persistenceErrorOperation {
                Text(L10n.format(operation == .read ? "Could not read group data: %@" : "Could not save group data: %@",
                                 detail, language: language)).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 540, height: 440)
    }
}
