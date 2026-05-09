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
        openMainInboxHandler?(source)
    }

    func openSettings() {
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
        AppWindowRouter.shared.openMainInbox(from: .dock)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func openSettingsFromPreferencesEvent() {
        AppWindowRouter.shared.openSettings()
    }

    @objc private func handleShowPreferences(
        event: NSAppleEventDescriptor,
        reply: NSAppleEventDescriptor
    ) {
        openSettingsFromPreferencesEvent()
    }
}
