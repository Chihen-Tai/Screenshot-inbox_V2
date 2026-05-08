import Foundation
import Testing
@testable import ScreenshotInbox

struct ScreenshotInboxPreferencesTests {
    @Test
    func defaultsMatchScreenshotInboxMVPBehavior() {
        let preferences = ScreenshotInboxPreferences.defaults

        #expect(preferences.autoCaptureEnabled)
        #expect(!preferences.screenshotFolderPath.isEmpty)
        #expect(preferences.floatingPreviewEnabled)
        #expect(preferences.floatingPreviewAutoShowEnabled)
        #expect(preferences.floatingPreviewDelay == 2.0)
        #expect(preferences.showMultipleScreenshotsInFloatingPreview)
        #expect(preferences.maxFloatingPreviewItems == 5)
        #expect(preferences.allowEmptyFloatingPreview)
        #expect(preferences.keepFloatingPreviewOpenWhileCollecting)
        #expect(preferences.menuBarEnabled)
        #expect(preferences.menuBarBadgeEnabled)
    }

    @Test
    func servicePersistsScreenshotInboxPreferences() {
        let suiteName = "ScreenshotInboxPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = ScreenshotInboxPreferencesService(defaults: defaults)

        let stored = ScreenshotInboxPreferences(
            autoCaptureEnabled: false,
            screenshotFolderPath: "/tmp/ScreenshotInboxPreferencesTests",
            floatingPreviewEnabled: false,
            floatingPreviewAutoShowEnabled: false,
            floatingPreviewDelay: 3.5,
            showMultipleScreenshotsInFloatingPreview: false,
            maxFloatingPreviewItems: 2,
            allowEmptyFloatingPreview: false,
            keepFloatingPreviewOpenWhileCollecting: false,
            menuBarEnabled: false,
            menuBarBadgeEnabled: false
        )

        service.preferences = stored

        #expect(service.preferences == stored)
    }
}
