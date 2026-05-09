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

enum AIProvider: String, CaseIterable, Hashable {
    case localRules
    case googleAIStudioGemma

    var title: String {
        switch self {
        case .localRules: return "Local Rules"
        case .googleAIStudioGemma: return "Google AI Studio"
        }
    }
}

enum GoogleAIStudioModel: String, CaseIterable, Hashable {
    case gemini25FlashLite = "gemini-2.5-flash-lite"
    case gemma4_26b = "gemma-4-26b-a4b-it"
    case gemma4_31b = "gemma-4-31b-it"

    var title: String {
        switch self {
        case .gemini25FlashLite: return "gemini-2.5-flash-lite (default)"
        case .gemma4_26b: return "gemma-4-26b-a4b-it"
        case .gemma4_31b: return "gemma-4-31b-it"
        }
    }
}

struct AppPreferences: Hashable {
    var autoImportEnabled: Bool
    var defaultWatchedFoldersInitialized: Bool
    var syncRenameOriginalSourceFiles: Bool
    var syncMoveOriginalToTrashOnAppTrash: Bool
    var syncMoveOriginalToTrashOnPermanentDelete: Bool
    var syncTrashInboxItemWhenOriginalDeleted: Bool
    var syncRenameInboxItemWhenOriginalRenamed: Bool
    var copyNewImportsToDefaultSourceFolder: Bool
    var defaultSourceFolderPath: String
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
    var aiInlineSuggestionsEnabled: Bool
    var aiSuggestFilenames: Bool
    var aiSuggestTags: Bool
    var aiUseLocalRules: Bool
    var aiProvider: AIProvider
    var googleAIStudioModel: GoogleAIStudioModel
    var aiVisionEnabled: Bool
    var aiVisionOnlyWhenOCREmpty: Bool

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
        syncRenameOriginalSourceFiles: false,
        syncMoveOriginalToTrashOnAppTrash: false,
        syncMoveOriginalToTrashOnPermanentDelete: false,
        syncTrashInboxItemWhenOriginalDeleted: false,
        syncRenameInboxItemWhenOriginalRenamed: false,
        copyNewImportsToDefaultSourceFolder: false,
        defaultSourceFolderPath: "~/Desktop",
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
        showDebugControls: false,
        aiInlineSuggestionsEnabled: true,
        aiSuggestFilenames: true,
        aiSuggestTags: true,
        aiUseLocalRules: true,
        aiProvider: .localRules,
        googleAIStudioModel: .gemini25FlashLite,
        aiVisionEnabled: false,
        aiVisionOnlyWhenOCREmpty: false
    )
}
