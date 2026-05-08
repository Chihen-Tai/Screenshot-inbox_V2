import AppKit

@MainActor
enum AppWindowOpenSource: Equatable {
    case menuBar
    case floatingPreview
    case dock
}

@MainActor
final class AppWindowRouter {
    static let shared = AppWindowRouter()

    private var openMainInboxHandler: ((AppWindowOpenSource) -> Void)?
    private var openSettingsHandler: (() -> Void)?

    func registerOpenMainInbox(_ handler: @escaping (AppWindowOpenSource) -> Void) {
        openMainInboxHandler = handler
    }

    func registerOpenSettings(_ handler: @escaping () -> Void) {
        openSettingsHandler = handler
    }

    func openMainInbox(from source: AppWindowOpenSource) {
        if source == .dock {
            print("[Dock] Opening Main Inbox")
        }
        openMainInboxHandler?(source)
    }

    func openSettings() {
        print("[Settings] openSettings() called")
        openSettingsHandler?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleShowPreferences(event:reply:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEShowPreferences)
        )
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        print("[Dock] App icon clicked / applicationShouldHandleReopen")
        AppWindowRouter.shared.openMainInbox(from: .dock)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("[Lifecycle] keeping app alive after last window closed")
        return false
    }

    func openSettingsFromPreferencesEvent() {
        print("[Settings] Preferences Apple Event received")
        AppWindowRouter.shared.openSettings()
    }

    @objc private func handleShowPreferences(
        event: NSAppleEventDescriptor,
        reply: NSAppleEventDescriptor
    ) {
        openSettingsFromPreferencesEvent()
    }
}
