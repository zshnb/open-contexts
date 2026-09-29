import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es, fr, ja, zh

    var id: String { rawValue }
    var resolvedCode: String {
        let code = self == .system ? Locale.preferredLanguages.first ?? "en" : rawValue
        let primary = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? "en"
        return ["en", "es", "fr", "ja", "zh"].contains(primary) ? primary : "en"
    }

    var name: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        case .ja: return "日本語"
        case .zh: return "中文"
        }
    }
}

enum L10n {
    static func text(_ key: String, language: AppLanguage) -> String {
        let path = Bundle.module.path(forResource: language.resolvedCode, ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.module
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ value: String, language: AppLanguage) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language.resolvedCode), value)
    }

    static func selfCheck() -> Bool {
        var expected: Set<String>?
        for language in AppLanguage.allCases where language != .system {
            guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj")
                    .map({ URL(fileURLWithPath: $0).appendingPathComponent("Localizable.strings") }),
                  let data = try? Data(contentsOf: path),
                  let entries = try? PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: String],
                  !entries.isEmpty, entries.values.allSatisfy({ !$0.isEmpty }) else { return false }
            let keys = Set(entries.keys)
            if let expected, expected != keys { return false }
            guard text("Ungrouped", language: language) == entries["Ungrouped"] else { return false }
            expected = keys
        }
        return AppLanguage.en.resolvedCode == "en"
            && AppLanguage.es.resolvedCode == "es"
            && AppLanguage.fr.resolvedCode == "fr"
            && AppLanguage.ja.resolvedCode == "ja"
            && AppLanguage.zh.resolvedCode == "zh"
            && text("Ungrouped", language: .ja) == "未分類"
    }
}
