import Foundation

enum PreferredAppearance: String, CaseIterable, Hashable {
    case system
    case light
    case dark

    var title: String { rawValue.capitalized }
}

enum OCRLanguagePreset: String, CaseIterable, Hashable {
    case chineseEnglish
    case englishOnly
    case chinesePriority

    var title: String {
        switch self {
        case .chineseEnglish: return "Chinese + English"
        case .englishOnly: return "English Only"
        case .chinesePriority: return "Chinese Priority"
        }
    }

    var languages: [String] {
        switch self {
        case .chineseEnglish, .chinesePriority:
            return ["zh-Hant", "zh-Hans", "en-US"]
        case .englishOnly:
            return ["en-US"]
        }
    }
}

struct AppPreferences: Hashable {
    var autoImportEnabled: Bool
    var defaultWatchedFoldersInitialized: Bool
    var renameOriginalSourceFiles: Bool
    var inspectorVisibleByDefault: Bool
    var sidebarVisibleByDefault: Bool
    var sidebarPanelWidth: Double
    var inspectorPanelWidth: Double
    var preferredAppearance: PreferredAppearance
    var ocrLanguagePreset: OCRLanguagePreset
    var ocrPreferredLanguages: [String]
    var showDebugControls: Bool

    static let defaults = AppPreferences(
        autoImportEnabled: true,
        defaultWatchedFoldersInitialized: false,
        renameOriginalSourceFiles: false,
        inspectorVisibleByDefault: true,
        sidebarVisibleByDefault: true,
        sidebarPanelWidth: 220,
        inspectorPanelWidth: 320,
        preferredAppearance: .system,
        ocrLanguagePreset: .chineseEnglish,
        ocrPreferredLanguages: ["zh-Hant", "zh-Hans", "en-US"],
        showDebugControls: false
    )
}
