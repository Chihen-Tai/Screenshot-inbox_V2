import Foundation

/// User-preference persistence backed by UserDefaults + bookmark store.
final class SettingsService {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferences: AppPreferences {
        get {
            let fallback = AppPreferences.defaults
            let appearance = PreferredAppearance(
                rawValue: defaults.string(forKey: Keys.preferredAppearance) ?? fallback.preferredAppearance.rawValue
            ) ?? fallback.preferredAppearance
            let ocrPreset = OCRLanguagePreset(
                rawValue: defaults.string(forKey: Keys.ocrLanguagePreset) ?? fallback.ocrLanguagePreset.rawValue
            ) ?? fallback.ocrLanguagePreset
            let languages = defaults.stringArray(forKey: Keys.ocrPreferredLanguages) ?? ocrPreset.languages
            return AppPreferences(
                autoImportEnabled: bool(Keys.autoImportEnabled, fallback.autoImportEnabled),
                defaultWatchedFoldersInitialized: bool(Keys.defaultWatchedFoldersInitialized, fallback.defaultWatchedFoldersInitialized),
                syncRenameOriginalSourceFiles: bool(Keys.syncRenameOriginalSourceFiles, fallback.syncRenameOriginalSourceFiles),
                syncMoveOriginalToTrashOnAppTrash: bool(Keys.syncMoveOriginalToTrashOnAppTrash, fallback.syncMoveOriginalToTrashOnAppTrash),
                syncMoveOriginalToTrashOnPermanentDelete: bool(Keys.syncMoveOriginalToTrashOnPermanentDelete, fallback.syncMoveOriginalToTrashOnPermanentDelete),
                syncTrashInboxItemWhenOriginalDeleted: bool(Keys.syncTrashInboxItemWhenOriginalDeleted, fallback.syncTrashInboxItemWhenOriginalDeleted),
                syncRenameInboxItemWhenOriginalRenamed: bool(Keys.syncRenameInboxItemWhenOriginalRenamed, fallback.syncRenameInboxItemWhenOriginalRenamed),
                copyNewImportsToDefaultSourceFolder: bool(Keys.copyNewImportsToDefaultSourceFolder, fallback.copyNewImportsToDefaultSourceFolder),
                defaultSourceFolderPath: defaults.string(forKey: Keys.defaultSourceFolderPath) ?? fallback.defaultSourceFolderPath,
                inspectorVisibleByDefault: bool(Keys.inspectorVisibleByDefault, fallback.inspectorVisibleByDefault),
                sidebarVisibleByDefault: bool(Keys.sidebarVisibleByDefault, fallback.sidebarVisibleByDefault),
                sidebarPanelWidth: double(Keys.sidebarPanelWidth, fallback.sidebarPanelWidth),
                inspectorPanelWidth: double(Keys.inspectorPanelWidth, fallback.inspectorPanelWidth),
                gridThumbnailSize: GridThumbnailSize(
                    rawValue: defaults.string(forKey: Keys.gridThumbnailSize) ?? fallback.gridThumbnailSize.rawValue
                ) ?? fallback.gridThumbnailSize,
                screenshotSortField: ScreenshotSortField(
                    rawValue: defaults.string(forKey: Keys.screenshotSortField) ?? fallback.screenshotSortField.rawValue
                ) ?? fallback.screenshotSortField,
                screenshotSortDirection: SortDirection(
                    rawValue: defaults.string(forKey: Keys.screenshotSortDirection) ?? fallback.screenshotSortDirection.rawValue
                ) ?? fallback.screenshotSortDirection,
                quickFilters: quickFilters(fallback: fallback.quickFilters),
                preferredAppearance: appearance,
                ocrLanguagePreset: ocrPreset,
                ocrPreferredLanguages: languages,
                showDebugControls: bool(Keys.showDebugControls, fallback.showDebugControls)
            )
        }
        set { save(newValue) }
    }

    func save(_ preferences: AppPreferences) {
        defaults.set(preferences.autoImportEnabled, forKey: Keys.autoImportEnabled)
        defaults.set(preferences.defaultWatchedFoldersInitialized, forKey: Keys.defaultWatchedFoldersInitialized)
        defaults.set(preferences.syncRenameOriginalSourceFiles, forKey: Keys.syncRenameOriginalSourceFiles)
        defaults.set(preferences.syncMoveOriginalToTrashOnAppTrash, forKey: Keys.syncMoveOriginalToTrashOnAppTrash)
        defaults.set(preferences.syncMoveOriginalToTrashOnPermanentDelete, forKey: Keys.syncMoveOriginalToTrashOnPermanentDelete)
        defaults.set(preferences.syncTrashInboxItemWhenOriginalDeleted, forKey: Keys.syncTrashInboxItemWhenOriginalDeleted)
        defaults.set(preferences.syncRenameInboxItemWhenOriginalRenamed, forKey: Keys.syncRenameInboxItemWhenOriginalRenamed)
        defaults.set(preferences.copyNewImportsToDefaultSourceFolder, forKey: Keys.copyNewImportsToDefaultSourceFolder)
        defaults.set(preferences.defaultSourceFolderPath, forKey: Keys.defaultSourceFolderPath)
        defaults.set(preferences.inspectorVisibleByDefault, forKey: Keys.inspectorVisibleByDefault)
        defaults.set(preferences.sidebarVisibleByDefault, forKey: Keys.sidebarVisibleByDefault)
        defaults.set(preferences.sidebarPanelWidth, forKey: Keys.sidebarPanelWidth)
        defaults.set(preferences.inspectorPanelWidth, forKey: Keys.inspectorPanelWidth)
        defaults.set(preferences.gridThumbnailSize.rawValue, forKey: Keys.gridThumbnailSize)
        defaults.set(preferences.screenshotSortField.rawValue, forKey: Keys.screenshotSortField)
        defaults.set(preferences.screenshotSortDirection.rawValue, forKey: Keys.screenshotSortDirection)
        defaults.set(encodeQuickFilters(preferences.quickFilters), forKey: Keys.quickFilters)
        defaults.set(preferences.preferredAppearance.rawValue, forKey: Keys.preferredAppearance)
        defaults.set(preferences.ocrLanguagePreset.rawValue, forKey: Keys.ocrLanguagePreset)
        defaults.set(preferences.ocrPreferredLanguages, forKey: Keys.ocrPreferredLanguages)
        defaults.set(preferences.showDebugControls, forKey: Keys.showDebugControls)
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func double(_ key: String, _ fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private func quickFilters(fallback: [QuickFilterPreference]) -> [QuickFilterPreference] {
        guard let stored = defaults.stringArray(forKey: Keys.quickFilters) else {
            return fallback
        }
        var decoded: [QuickFilterPreference] = []
        var seen = Set<FilterChip>()
        for item in stored {
            let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
            guard let raw = parts.first,
                  let chip = FilterChip(rawValue: raw),
                  !seen.contains(chip) else { continue }
            let isEnabled = parts.dropFirst().first.flatMap(Bool.init) ?? true
            decoded.append(QuickFilterPreference(chip: chip, isEnabled: isEnabled))
            seen.insert(chip)
        }
        for chip in FilterChip.allCases where !seen.contains(chip) {
            decoded.append(QuickFilterPreference(chip: chip, isEnabled: false))
        }
        return decoded
    }

    private func encodeQuickFilters(_ filters: [QuickFilterPreference]) -> [String] {
        filters.map { "\($0.chip.rawValue):\($0.isEnabled)" }
    }

    enum Keys {
        static let autoImportEnabled = "ScreenshotInbox.autoImport.enabled"
        static let defaultWatchedFoldersInitialized = "ScreenshotInbox.defaultWatchedFoldersInitialized"
        static let syncRenameOriginalSourceFiles = "ScreenshotInbox.syncRenameOriginalSourceFiles"
        static let syncMoveOriginalToTrashOnAppTrash = "ScreenshotInbox.syncMoveOriginalToTrashOnAppTrash"
        static let syncMoveOriginalToTrashOnPermanentDelete = "ScreenshotInbox.syncMoveOriginalToTrashOnPermanentDelete"
        static let syncTrashInboxItemWhenOriginalDeleted = "ScreenshotInbox.syncTrashInboxItemWhenOriginalDeleted"
        static let syncRenameInboxItemWhenOriginalRenamed = "ScreenshotInbox.syncRenameInboxItemWhenOriginalRenamed"
        static let copyNewImportsToDefaultSourceFolder = "ScreenshotInbox.copyNewImportsToDefaultSourceFolder"
        static let defaultSourceFolderPath = "ScreenshotInbox.defaultSourceFolderPath"
        static let inspectorVisibleByDefault = "ScreenshotInbox.inspectorVisibleByDefault"
        static let sidebarVisibleByDefault = "ScreenshotInbox.sidebarVisibleByDefault"
        static let sidebarPanelWidth = "ScreenshotInbox.layout.sidebarPanelWidth"
        static let inspectorPanelWidth = "ScreenshotInbox.layout.inspectorPanelWidth"
        static let gridThumbnailSize = "ScreenshotInbox.grid.thumbnailSize"
        static let screenshotSortField = "ScreenshotInbox.grid.sortField"
        static let screenshotSortDirection = "ScreenshotInbox.grid.sortDirection"
        static let quickFilters = "ScreenshotInbox.quickFilters"
        static let preferredAppearance = "ScreenshotInbox.preferredAppearance"
        static let ocrLanguagePreset = "ScreenshotInbox.ocrLanguagePreset"
        static let ocrPreferredLanguages = "ScreenshotInbox.ocrPreferredLanguages"
        static let showDebugControls = "ScreenshotInbox.debug.showDebugControls"
    }
}
