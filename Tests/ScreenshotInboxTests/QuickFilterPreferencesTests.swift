import Foundation
import Testing
@testable import ScreenshotInbox

struct QuickFilterPreferencesTests {
    @Test
    func filterChipCatalogIncludesCustomizableBuiltIns() {
        #expect(FilterChip.allCases == [
            .all,
            .favorites,
            .ocrComplete,
            .ocrPending,
            .tagged,
            .untagged,
            .png,
            .jpg,
            .heic,
            .hasQRCode,
            .hasURL,
            .today,
            .thisWeek
        ])
    }

    @Test
    func defaultEnabledQuickFiltersMatchReleaseToolbar() {
        #expect(AppPreferences.defaults.quickFilters.map(\.chip) == FilterChip.allCases)
        #expect(AppPreferences.defaults.quickFilters.filter(\.isEnabled).map(\.chip) == [
            .all,
            .favorites,
            .ocrComplete,
            .tagged,
            .png,
            .thisWeek
        ])
    }

    @Test
    func settingsServicePersistsQuickFilterOrderAndVisibility() {
        let suiteName = "ScreenshotInbox.QuickFilterPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = SettingsService(defaults: defaults)
        var preferences = AppPreferences.defaults
        preferences.quickFilters = [
            QuickFilterPreference(chip: .thisWeek, isEnabled: true),
            QuickFilterPreference(chip: .png, isEnabled: false),
            QuickFilterPreference(chip: .favorites, isEnabled: true)
        ]

        service.save(preferences)

        let loaded = service.preferences.quickFilters
        #expect(Array(loaded.prefix(preferences.quickFilters.count)) == preferences.quickFilters)
        #expect(loaded.contains(QuickFilterPreference(chip: .hasQRCode, isEnabled: false)))
    }

    @Test
    func settingsServiceRepairsMissingBuiltInQuickFilters() {
        let suiteName = "ScreenshotInbox.QuickFilterPreferencesRepairTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["PNG:false"], forKey: SettingsService.Keys.quickFilters)

        let filters = SettingsService(defaults: defaults).preferences.quickFilters

        #expect(filters.first == QuickFilterPreference(chip: .png, isEnabled: false))
        #expect(filters.contains(QuickFilterPreference(chip: .hasQRCode, isEnabled: false)))
        #expect(filters.contains(QuickFilterPreference(chip: .thisWeek, isEnabled: false)))
    }

    @Test
    func sourceFolderSyncPreferencesDefaultOffAndPersist() {
        let suiteName = "ScreenshotInbox.SourceFolderSyncPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = SettingsService(defaults: defaults)
        var preferences = service.preferences
        #expect(!preferences.syncRenameOriginalSourceFiles)
        #expect(!preferences.syncMoveOriginalToTrashOnAppTrash)
        #expect(!preferences.syncMoveOriginalToTrashOnPermanentDelete)
        #expect(!preferences.syncTrashInboxItemWhenOriginalDeleted)
        #expect(!preferences.syncRenameInboxItemWhenOriginalRenamed)
        #expect(!preferences.copyNewImportsToDefaultSourceFolder)
        #expect(preferences.defaultSourceFolderPath == "~/Desktop")

        preferences.syncRenameOriginalSourceFiles = true
        preferences.syncMoveOriginalToTrashOnAppTrash = true
        preferences.syncMoveOriginalToTrashOnPermanentDelete = true
        preferences.syncTrashInboxItemWhenOriginalDeleted = true
        preferences.syncRenameInboxItemWhenOriginalRenamed = true
        preferences.copyNewImportsToDefaultSourceFolder = true
        preferences.defaultSourceFolderPath = "/tmp/ScreenshotInboxSourceSync"
        service.save(preferences)

        let reloaded = service.preferences
        #expect(reloaded.syncRenameOriginalSourceFiles)
        #expect(reloaded.syncMoveOriginalToTrashOnAppTrash)
        #expect(reloaded.syncMoveOriginalToTrashOnPermanentDelete)
        #expect(reloaded.syncTrashInboxItemWhenOriginalDeleted)
        #expect(reloaded.syncRenameInboxItemWhenOriginalRenamed)
        #expect(reloaded.copyNewImportsToDefaultSourceFolder)
        #expect(reloaded.defaultSourceFolderPath == "/tmp/ScreenshotInboxSourceSync")
    }
}
