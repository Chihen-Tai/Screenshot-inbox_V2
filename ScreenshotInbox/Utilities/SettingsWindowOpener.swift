import AppKit
import SwiftUI

@MainActor
enum SettingsWindowOpener {
    private static var window: NSWindow?

    static func open(appState: AppState, selectedTab: SettingsTab = .general) {
        #if DEBUG
        print("[Settings] opening settings window")
        print("[Settings] preserving current destination: \(appState.sidebarSelection?.displayTitle ?? "nil")")
        #endif

        let rootView = SettingsView(initialTab: selectedTab)
            .environmentObject(appState)
            .preferredColorScheme(colorScheme(for: appState.preferences.preferredAppearance))

        if let existing = window {
            existing.contentViewController = NSHostingController(rootView: rootView)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            #if DEBUG
            print("[Settings] focused existing settings window")
            print("[Settings] did not change grid destination")
            #endif
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        let settingsWindow = NSWindow(contentViewController: hostingController)
        settingsWindow.title = "Settings"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.minSize = NSSize(width: 800, height: 520)
        settingsWindow.setContentSize(NSSize(width: 900, height: 620))
        settingsWindow.center()
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
