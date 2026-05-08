import AppKit
import SwiftUI

enum ScreenshotInboxWindowMetrics {
    static let defaultSize = NSSize(width: 1000, height: 700)
    static let minimumSize = NSSize(width: 760, height: 520)
    static let autosaveName = "ScreenshotInboxMainInboxWindow"
}

@MainActor
final class ScreenshotInboxWindowController: NSObject, NSWindowDelegate {
    static let shared = ScreenshotInboxWindowController()

    private var window: NSWindow?

    private override init() {}

    func open(appState: AppState, source: AppWindowOpenSource) {
        if source == .dock {
            print("[MainInbox] show() called from Dock")
        } else {
            print("[MainInbox] show() called")
        }
        print("[MainInbox] store item count = \(appState.screenshotInboxStore.allItems.count)")
        QuickLookPreviewController.shared.close()
        FloatingInboxPanelController.shared.hide()

        if let existingWindow = window {
            print("[MainInbox] reusing existing window")
            NSApp.setActivationPolicy(.regular)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.deminiaturize(nil)
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            print("[MainInbox] window made key and front")
            return
        }

        print("[MainInbox] creating new window")
        let rootView = MainWindowView()
            .environmentObject(appState)
            .preferredColorScheme(colorScheme(for: appState.preferences.preferredAppearance))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ScreenshotInboxWindowMetrics.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot Inbox"
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.minSize = ScreenshotInboxWindowMetrics.minimumSize
        window.delegate = self
        window.setFrameAutosaveName(ScreenshotInboxWindowMetrics.autosaveName)

        if !window.setFrameUsingName(ScreenshotInboxWindowMetrics.autosaveName) {
            window.setContentSize(ScreenshotInboxWindowMetrics.defaultSize)
            window.center()
        }

        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        print("[MainInbox] window made key and front")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func colorScheme(for appearance: PreferredAppearance) -> ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
