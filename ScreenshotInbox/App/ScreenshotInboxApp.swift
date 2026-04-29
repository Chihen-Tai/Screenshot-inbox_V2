import SwiftUI
import AppKit

@main
struct ScreenshotInboxApp: App {
    @StateObject private var appState = AppState()

    // SPM executable targets launch without a proper app bundle, so the
    // activation policy defaults to something that suppresses the menu bar
    // and starves SwiftUI's `keyboardShortcut` of a place to register. Force
    // `.regular` + `activate(...)` so Cmd-A reaches the app at all.
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let appIcon = Self.appIconImage() {
            NSApplication.shared.applicationIconImage = appIcon
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        print("[App] init; activationPolicy set to .regular and activated")
    }

    var body: some Scene {
        WindowGroup("Screenshot Inbox") {
            MainWindowView()
                .environmentObject(appState)
                .preferredColorScheme(colorScheme)
                .frame(
                    minWidth: Theme.Layout.minWindowWidth,
                    minHeight: Theme.Layout.minWindowHeight
                )
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appState.preferences.preferredAppearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private static func appIconImage() -> NSImage? {
        if let assetIcon = NSImage(named: "AppIcon") {
            return assetIcon
        }
        return Bundle.module.url(
            forResource: "icon_512x512@2x",
            withExtension: "png",
            subdirectory: "Assets.xcassets/AppIcon.appiconset"
        ).flatMap(NSImage.init(contentsOf:))
    }
}
