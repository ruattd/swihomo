import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .light: "preferences.appearance.light"
        case .dark: "preferences.appearance.dark"
        case .system: "preferences.appearance.system"
        }
    }

    var subtitle: String {
        switch self {
        case .light: "Always light"
        case .dark: "Always dark"
        case .system: "Match device"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .light: "preferences.appearance.lightDescription"
        case .dark: "preferences.appearance.darkDescription"
        case .system: "preferences.appearance.systemDescription"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .system: "circle.lefthalf.filled"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
