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
                renameOriginalSourceFiles: bool(Keys.renameOriginalSourceFiles, fallback.renameOriginalSourceFiles),
                inspectorVisibleByDefault: bool(Keys.inspectorVisibleByDefault, fallback.inspectorVisibleByDefault),
                sidebarVisibleByDefault: bool(Keys.sidebarVisibleByDefault, fallback.sidebarVisibleByDefault),
                sidebarPanelWidth: double(Keys.sidebarPanelWidth, fallback.sidebarPanelWidth),
                inspectorPanelWidth: double(Keys.inspectorPanelWidth, fallback.inspectorPanelWidth),
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
        defaults.set(preferences.renameOriginalSourceFiles, forKey: Keys.renameOriginalSourceFiles)
        defaults.set(preferences.inspectorVisibleByDefault, forKey: Keys.inspectorVisibleByDefault)
        defaults.set(preferences.sidebarVisibleByDefault, forKey: Keys.sidebarVisibleByDefault)
        defaults.set(preferences.sidebarPanelWidth, forKey: Keys.sidebarPanelWidth)
        defaults.set(preferences.inspectorPanelWidth, forKey: Keys.inspectorPanelWidth)
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

    enum Keys {
        static let autoImportEnabled = "ScreenshotInbox.autoImport.enabled"
        static let defaultWatchedFoldersInitialized = "ScreenshotInbox.defaultWatchedFoldersInitialized"
        static let renameOriginalSourceFiles = "ScreenshotInbox.renameOriginalSourceFiles"
        static let inspectorVisibleByDefault = "ScreenshotInbox.inspectorVisibleByDefault"
        static let sidebarVisibleByDefault = "ScreenshotInbox.sidebarVisibleByDefault"
        static let sidebarPanelWidth = "ScreenshotInbox.layout.sidebarPanelWidth"
        static let inspectorPanelWidth = "ScreenshotInbox.layout.inspectorPanelWidth"
        static let preferredAppearance = "ScreenshotInbox.preferredAppearance"
        static let ocrLanguagePreset = "ScreenshotInbox.ocrLanguagePreset"
        static let ocrPreferredLanguages = "ScreenshotInbox.ocrPreferredLanguages"
        static let showDebugControls = "ScreenshotInbox.debug.showDebugControls"
    }
}
