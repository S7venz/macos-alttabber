import AppKit
import CoreGraphics

// MARK: - Option enums

/// The modifier the user holds to summon the switcher.
enum HoldModifier: String, CaseIterable, Identifiable {
    case option, command, control
    var id: String { rawValue }

    var label: String {
        switch self {
        case .option:  return "⌥  Option"
        case .command: return "⌘  Command"
        case .control: return "⌃  Control"
        }
    }

    /// CGEvent flag used by the event tap.
    var cgFlag: CGEventFlags {
        switch self {
        case .option:  return .maskAlternate
        case .command: return .maskCommand
        case .control: return .maskControl
        }
    }

    var warning: String? {
        switch self {
        case .command: return "Remplace le sélecteur d'apps système ⌘⇥."
        default:       return nil
        }
    }
}

enum ThumbnailSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:  return "Petit"
        case .medium: return "Moyen"
        case .large:  return "Grand"
        }
    }

    var cardWidth: CGFloat {
        switch self {
        case .small:  return 172
        case .medium: return 222
        case .large:  return 282
        }
    }

    var cardHeight: CGFloat {
        switch self {
        case .small:  return 132
        case .medium: return 170
        case .large:  return 214
        }
    }

    /// Longest edge of the captured bitmap.
    var maxThumbDimension: CGFloat {
        switch self {
        case .small:  return 520
        case .medium: return 760
        case .large:  return 960
        }
    }
}

enum ActivationStyle: String, CaseIterable, Identifiable {
    case hold, stayOpen
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hold:     return "Maintenir (relâcher pour valider)"
        case .stayOpen: return "Rester ouvert (Tab / Entrée / Échap)"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto, dark, light
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:  return "Automatique"
        case .dark:  return "Sombre"
        case .light: return "Clair"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .auto:  return nil
        case .dark:  return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }
}

// MARK: - Settings store

/// Observable, UserDefaults-backed settings shared across the app.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var modifier: HoldModifier { didSet { defaults.set(modifier.rawValue, forKey: Keys.modifier) } }
    @Published var activationStyle: ActivationStyle { didSet { defaults.set(activationStyle.rawValue, forKey: Keys.activationStyle) } }
    @Published var includeMinimized: Bool { didSet { defaults.set(includeMinimized, forKey: Keys.includeMinimized) } }
    @Published var allSpaces: Bool { didSet { defaults.set(allSpaces, forKey: Keys.allSpaces) } }
    @Published var thumbnailSize: ThumbnailSize { didSet { defaults.set(thumbnailSize.rawValue, forKey: Keys.thumbnailSize) } }
    @Published var maxColumns: Int { didSet { defaults.set(maxColumns, forKey: Keys.maxColumns) } }
    @Published var showTitles: Bool { didSet { defaults.set(showTitles, forKey: Keys.showTitles) } }
    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    @Published var animations: Bool { didSet { defaults.set(animations, forKey: Keys.animations) } }

    private enum Keys {
        static let modifier = "modifier"
        static let activationStyle = "activationStyle"
        static let includeMinimized = "includeMinimized"
        static let allSpaces = "allSpaces"
        static let thumbnailSize = "thumbnailSize"
        static let maxColumns = "maxColumns"
        static let showTitles = "showTitles"
        static let appearance = "appearance"
        static let animations = "animations"
    }

    private init() {
        defaults.register(defaults: [
            Keys.modifier: HoldModifier.option.rawValue,
            Keys.activationStyle: ActivationStyle.hold.rawValue,
            Keys.includeMinimized: true,
            Keys.allSpaces: true,
            Keys.thumbnailSize: ThumbnailSize.medium.rawValue,
            Keys.maxColumns: 6,
            Keys.showTitles: true,
            Keys.appearance: AppearanceMode.auto.rawValue,
            Keys.animations: true
        ])
        // didSet does not fire during init, so these are plain loads.
        modifier = HoldModifier(rawValue: defaults.string(forKey: Keys.modifier) ?? "") ?? .option
        activationStyle = ActivationStyle(rawValue: defaults.string(forKey: Keys.activationStyle) ?? "") ?? .hold
        includeMinimized = defaults.bool(forKey: Keys.includeMinimized)
        allSpaces = defaults.bool(forKey: Keys.allSpaces)
        thumbnailSize = ThumbnailSize(rawValue: defaults.string(forKey: Keys.thumbnailSize) ?? "") ?? .medium
        maxColumns = max(1, defaults.integer(forKey: Keys.maxColumns))
        showTitles = defaults.bool(forKey: Keys.showTitles)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .auto
        animations = defaults.bool(forKey: Keys.animations)
    }
}
