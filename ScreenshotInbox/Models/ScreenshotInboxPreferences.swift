import Foundation

struct ScreenshotInboxPreferences: Equatable {
    var autoCaptureEnabled: Bool
    var screenshotFolderPath: String
    /// Master switch — if false, floating preview never appears automatically.
    var floatingPreviewEnabled: Bool
    /// Whether the panel auto-pops after a screenshot is captured.
    /// Requires floatingPreviewEnabled = true to have any effect.
    var floatingPreviewAutoShowEnabled: Bool
    var floatingPreviewDelay: Double
    var showMultipleScreenshotsInFloatingPreview: Bool
    var maxFloatingPreviewItems: Int
    var allowEmptyFloatingPreview: Bool
    var keepFloatingPreviewOpenWhileCollecting: Bool
    var menuBarEnabled: Bool
    var menuBarBadgeEnabled: Bool

    static let defaults = ScreenshotInboxPreferences(
        autoCaptureEnabled: true,
        screenshotFolderPath: ScreenshotWatcher.defaultScreenshotFolderURL().path,
        floatingPreviewEnabled: true,
        floatingPreviewAutoShowEnabled: true,
        floatingPreviewDelay: 2.0,
        showMultipleScreenshotsInFloatingPreview: true,
        maxFloatingPreviewItems: 5,
        allowEmptyFloatingPreview: true,
        keepFloatingPreviewOpenWhileCollecting: true,
        menuBarEnabled: true,
        menuBarBadgeEnabled: true
    )
}

final class ScreenshotInboxPreferencesService {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferences: ScreenshotInboxPreferences {
        get {
            let fallback = ScreenshotInboxPreferences.defaults
            return ScreenshotInboxPreferences(
                autoCaptureEnabled: bool(Keys.autoCaptureEnabled, fallback.autoCaptureEnabled),
                screenshotFolderPath: string(Keys.screenshotFolderPath, fallback.screenshotFolderPath),
                floatingPreviewEnabled: bool(Keys.floatingPreviewEnabled, fallback.floatingPreviewEnabled),
                floatingPreviewAutoShowEnabled: bool(Keys.floatingPreviewAutoShowEnabled, fallback.floatingPreviewAutoShowEnabled),
                floatingPreviewDelay: double(Keys.floatingPreviewDelay, fallback.floatingPreviewDelay),
                showMultipleScreenshotsInFloatingPreview: bool(
                    Keys.showMultipleScreenshotsInFloatingPreview,
                    fallback.showMultipleScreenshotsInFloatingPreview
                ),
                maxFloatingPreviewItems: max(1, integer(Keys.maxFloatingPreviewItems, fallback.maxFloatingPreviewItems)),
                allowEmptyFloatingPreview: bool(Keys.allowEmptyFloatingPreview, fallback.allowEmptyFloatingPreview),
                keepFloatingPreviewOpenWhileCollecting: bool(
                    Keys.keepFloatingPreviewOpenWhileCollecting,
                    fallback.keepFloatingPreviewOpenWhileCollecting
                ),
                menuBarEnabled: bool(Keys.menuBarEnabled, fallback.menuBarEnabled),
                menuBarBadgeEnabled: bool(Keys.menuBarBadgeEnabled, fallback.menuBarBadgeEnabled)
            )
        }
        set {
            defaults.set(newValue.autoCaptureEnabled, forKey: Keys.autoCaptureEnabled)
            defaults.set(newValue.screenshotFolderPath, forKey: Keys.screenshotFolderPath)
            defaults.set(newValue.floatingPreviewEnabled, forKey: Keys.floatingPreviewEnabled)
            defaults.set(newValue.floatingPreviewAutoShowEnabled, forKey: Keys.floatingPreviewAutoShowEnabled)
            defaults.set(newValue.floatingPreviewDelay, forKey: Keys.floatingPreviewDelay)
            defaults.set(
                newValue.showMultipleScreenshotsInFloatingPreview,
                forKey: Keys.showMultipleScreenshotsInFloatingPreview
            )
            defaults.set(newValue.maxFloatingPreviewItems, forKey: Keys.maxFloatingPreviewItems)
            defaults.set(newValue.allowEmptyFloatingPreview, forKey: Keys.allowEmptyFloatingPreview)
            defaults.set(
                newValue.keepFloatingPreviewOpenWhileCollecting,
                forKey: Keys.keepFloatingPreviewOpenWhileCollecting
            )
            defaults.set(newValue.menuBarEnabled, forKey: Keys.menuBarEnabled)
            defaults.set(newValue.menuBarBadgeEnabled, forKey: Keys.menuBarBadgeEnabled)
        }
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func double(_ key: String, _ fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private func string(_ key: String, _ fallback: String) -> String {
        guard let value = defaults.string(forKey: key), !value.isEmpty else { return fallback }
        return value
    }

    private func integer(_ key: String, _ fallback: Int) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.integer(forKey: key)
    }

    enum Keys {
        static let autoCaptureEnabled = "ScreenshotInbox.phase1.autoCaptureEnabled"
        static let screenshotFolderPath = "ScreenshotInbox.phase1.screenshotFolderPath"
        static let floatingPreviewEnabled = "ScreenshotInbox.phase1.floatingPreviewEnabled"
        static let floatingPreviewAutoShowEnabled = "ScreenshotInbox.phase1.floatingPreviewAutoShowEnabled"
        static let floatingPreviewDelay = "ScreenshotInbox.phase1.floatingPreviewDelay"
        static let showMultipleScreenshotsInFloatingPreview = "ScreenshotInbox.phase1.showMultipleScreenshotsInFloatingPreview"
        static let maxFloatingPreviewItems = "ScreenshotInbox.phase1.maxFloatingPreviewItems"
        static let allowEmptyFloatingPreview = "ScreenshotInbox.phase1.allowEmptyFloatingPreview"
        static let keepFloatingPreviewOpenWhileCollecting = "ScreenshotInbox.phase1.keepFloatingPreviewOpenWhileCollecting"
        static let menuBarEnabled = "ScreenshotInbox.phase1.menuBarEnabled"
        static let menuBarBadgeEnabled = "ScreenshotInbox.phase1.menuBarBadgeEnabled"
    }
}
