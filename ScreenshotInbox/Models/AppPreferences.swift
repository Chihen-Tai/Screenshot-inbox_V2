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

enum GridThumbnailSize: String, CaseIterable, Hashable {
    case small
    case medium
    case large

    var title: String { rawValue.capitalized }
}

enum ScreenshotSortField: String, CaseIterable, Hashable {
    case createdDate
    case name
    case size

    var title: String {
        switch self {
        case .createdDate: return "Created Date"
        case .name: return "Name"
        case .size: return "Size"
        }
    }
}

enum SortDirection: String, CaseIterable, Hashable {
    case ascending
    case descending

    var title: String { rawValue.capitalized }
}

struct QuickFilterPreference: Hashable, Identifiable {
    var chip: FilterChip
    var isEnabled: Bool

    var id: FilterChip { chip }
}

struct AppPreferences: Hashable {
    var autoImportEnabled: Bool
    var defaultWatchedFoldersInitialized: Bool
    var renameOriginalSourceFiles: Bool
    var trashOriginalSourceFiles: Bool
    var deleteOriginalSourceFiles: Bool
    var copyNewScreenshotsToDefaultFolder: Bool
    var defaultCopyFolderPath: String
    var inspectorVisibleByDefault: Bool
    var sidebarVisibleByDefault: Bool
    var sidebarPanelWidth: Double
    var inspectorPanelWidth: Double
    var gridThumbnailSize: GridThumbnailSize
    var screenshotSortField: ScreenshotSortField
    var screenshotSortDirection: SortDirection
    var quickFilters: [QuickFilterPreference]
    var preferredAppearance: PreferredAppearance
    var ocrLanguagePreset: OCRLanguagePreset
    var ocrPreferredLanguages: [String]
    var showDebugControls: Bool

    static let defaultQuickFilters: [QuickFilterPreference] = [
        QuickFilterPreference(chip: .all, isEnabled: true),
        QuickFilterPreference(chip: .favorites, isEnabled: true),
        QuickFilterPreference(chip: .ocrComplete, isEnabled: true),
        QuickFilterPreference(chip: .ocrPending, isEnabled: false),
        QuickFilterPreference(chip: .tagged, isEnabled: true),
        QuickFilterPreference(chip: .untagged, isEnabled: false),
        QuickFilterPreference(chip: .png, isEnabled: true),
        QuickFilterPreference(chip: .jpg, isEnabled: false),
        QuickFilterPreference(chip: .heic, isEnabled: false),
        QuickFilterPreference(chip: .hasQRCode, isEnabled: false),
        QuickFilterPreference(chip: .hasURL, isEnabled: false),
        QuickFilterPreference(chip: .today, isEnabled: false),
        QuickFilterPreference(chip: .thisWeek, isEnabled: true)
    ]

    static let defaults = AppPreferences(
        autoImportEnabled: true,
        defaultWatchedFoldersInitialized: false,
        renameOriginalSourceFiles: false,
        trashOriginalSourceFiles: false,
        deleteOriginalSourceFiles: false,
        copyNewScreenshotsToDefaultFolder: false,
        defaultCopyFolderPath: "~/Desktop",
        inspectorVisibleByDefault: true,
        sidebarVisibleByDefault: true,
        sidebarPanelWidth: 220,
        inspectorPanelWidth: 320,
        gridThumbnailSize: .medium,
        screenshotSortField: .createdDate,
        screenshotSortDirection: .descending,
        quickFilters: defaultQuickFilters,
        preferredAppearance: .system,
        ocrLanguagePreset: .chineseEnglish,
        ocrPreferredLanguages: ["zh-Hant", "zh-Hans", "en-US"],
        showDebugControls: false
    )
}
