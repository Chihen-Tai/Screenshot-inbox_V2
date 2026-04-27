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
        NSApplication.shared.activate(ignoringOtherApps: true)
        print("[App] init; activationPolicy set to .regular and activated")
    }

    var body: some Scene {
        WindowGroup("Screenshot Inbox") {
            MainWindowView()
                .environmentObject(appState)
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
        }
    }
}
