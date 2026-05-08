import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {}

    func show(appState: AppState) {
        QuickLookPreviewController.shared.close()
        if let existingWindow = window {
            print("[Settings] reusing existing Settings window")
            NSApp.setActivationPolicy(.regular)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.deminiaturize(nil)
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            print("[Settings] Settings window shown")
            return
        }

        print("[Settings] creating Settings window size = 680x640")
        let rootView = SettingsView()
            .environmentObject(appState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

        let hostingController = NSHostingController(rootView: rootView)
        print("[Settings] SettingsView loaded")

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Settings"
        newWindow.isOpaque = true
        newWindow.backgroundColor = .windowBackgroundColor
        newWindow.minSize = NSSize(width: 620, height: 520)
        newWindow.contentViewController = hostingController
        print("[Settings] contentViewController assigned")
        newWindow.setContentSize(NSSize(width: 680, height: 640))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        self.window = newWindow

        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        print("[Settings] Settings window shown")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
