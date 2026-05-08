import Testing
import AppKit
@testable import ScreenshotInbox

@Suite("Screenshot inbox window")
struct ScreenshotInboxWindowTests {
    @Test("main inbox window uses a usable default size and autosave name")
    func windowMetricsAreUsable() {
        #expect(ScreenshotInboxWindowMetrics.defaultSize.width >= 900)
        #expect(ScreenshotInboxWindowMetrics.defaultSize.width <= 1200)
        #expect(ScreenshotInboxWindowMetrics.defaultSize.height >= 600)
        #expect(ScreenshotInboxWindowMetrics.defaultSize.height <= 800)
        #expect(ScreenshotInboxWindowMetrics.minimumSize.width >= 700)
        #expect(ScreenshotInboxWindowMetrics.minimumSize.height >= 450)
        #expect(!ScreenshotInboxWindowMetrics.autosaveName.isEmpty)
    }

    @Test("floating preview header count uses total new count")
    func floatingPreviewHeaderCountUsesTotalNewCount() {
        #expect(FloatingPreviewHeaderCount.title(totalNewCount: 35) == "35 new")
        #expect(FloatingPreviewHeaderCount.title(totalNewCount: 1) == "1 new")
        #expect(FloatingPreviewHeaderCount.title(totalNewCount: 0) == nil)
    }

    @MainActor
    @Test("Dock reopen uses the registered main inbox route")
    func dockReopenUsesRegisteredMainInboxRoute() {
        let router = AppWindowRouter()
        var openedSource: AppWindowOpenSource?
        router.registerOpenMainInbox { source in
            openedSource = source
        }

        router.openMainInbox(from: .dock)

        #expect(openedSource == .dock)
    }

    @MainActor
    @Test("App delegate handles Dock reopen without default window creation")
    func appDelegateHandlesDockReopen() {
        var openedSource: AppWindowOpenSource?
        AppWindowRouter.shared.registerOpenMainInbox { source in
            openedSource = source
        }

        let shouldUseDefaultReopen = AppDelegate().applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        #expect(shouldUseDefaultReopen == false)
        #expect(openedSource == .dock)
    }

    @MainActor
    @Test("App delegate keeps the menu bar app alive after windows close")
    func appDelegateKeepsAppAliveAfterLastWindowClosed() {
        let shouldTerminate = AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)

        #expect(shouldTerminate == false)
    }

    @MainActor
    @Test("App delegate routes standard Preferences events to the shared settings window")
    func appDelegateRoutesPreferencesEventToSettings() {
        var didOpenSettings = false
        AppWindowRouter.shared.registerOpenSettings {
            didOpenSettings = true
        }

        AppDelegate().openSettingsFromPreferencesEvent()

        #expect(didOpenSettings)
    }
}
