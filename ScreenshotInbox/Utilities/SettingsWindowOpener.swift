import AppKit
import SwiftUI

@MainActor
enum SettingsWindowOpener {
    private static var window: NSWindow?

    static func open(appState: AppState) {
        #if DEBUG
        print("[Settings] opening settings window")
        print("[Settings] preserving current destination: \(appState.sidebarSelection?.displayTitle ?? "nil")")
        #endif

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            #if DEBUG
            print("[Settings] focused existing settings window")
            print("[Settings] did not change grid destination")
            #endif
            return
        }

        let rootView = SettingsView()
            .environmentObject(appState)
            .preferredColorScheme(colorScheme(for: appState.preferences.preferredAppearance))
        let hostingController = NSHostingController(rootView: rootView)
        let settingsWindow = NSWindow(contentViewController: hostingController)
        settingsWindow.title = "Settings"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.center()
        settingsWindow.setContentSize(NSSize(width: 640, height: 480))
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = settingsWindow
        #if DEBUG
        print("[Settings] did not change grid destination")
        #endif
    }

    private static func colorScheme(for appearance: PreferredAppearance) -> ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
