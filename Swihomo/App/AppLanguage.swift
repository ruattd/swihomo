import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey? {
        switch self {
        case .system: "preferences.language.systemDefault"
        case .english, .simplifiedChinese: nil
        }
    }

    var endonym: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .current
        default: Locale(identifier: self.id)
        }
    }
}
