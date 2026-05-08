import Foundation
import Testing
@testable import ScreenshotInbox

struct SingleInstanceGuardTests {
    @Test
    func keepsCurrentProcessWhenNoMatchingInstanceExists() {
        let current = ScreenshotInboxSingleInstanceGuard.AppIdentity(
            processIdentifier: 10,
            bundleIdentifier: "com.example.ScreenshotInbox.debug",
            executableURL: URL(fileURLWithPath: "/tmp/ScreenshotInbox")
        )
        let other = ScreenshotInboxSingleInstanceGuard.AppIdentity(
            processIdentifier: 20,
            bundleIdentifier: "com.example.OtherApp",
            executableURL: URL(fileURLWithPath: "/Applications/Other.app/Contents/MacOS/Other")
        )

        let decision = ScreenshotInboxSingleInstanceGuard.evaluate(
            current: current,
            runningApplications: [current, other]
        )

        #expect(decision.result == .keepCurrent)
        #expect(decision.existingInstance == nil)
    }

    @Test
    func terminatesCurrentProcessWhenMatchingInstalledAppAlreadyRuns() {
        let current = ScreenshotInboxSingleInstanceGuard.AppIdentity(
            processIdentifier: 10,
            bundleIdentifier: nil,
            executableURL: URL(fileURLWithPath: "/Applications/codes/screenshot_V2/.build/arm64-apple-macosx/debug/ScreenshotInbox")
        )
        let installed = ScreenshotInboxSingleInstanceGuard.AppIdentity(
            processIdentifier: 20,
            bundleIdentifier: "com.example.ScreenshotInbox",
            executableURL: URL(fileURLWithPath: "/Applications/Screenshot Inbox.app/Contents/MacOS/ScreenshotInbox")
        )

        let decision = ScreenshotInboxSingleInstanceGuard.evaluate(
            current: current,
            runningApplications: [current, installed]
        )

        #expect(decision.result == .terminateCurrent)
        #expect(decision.existingInstance?.processIdentifier == 20)
    }

    @Test
    func debugBundleIdentifierDoesNotMatchReleaseBundleIdentifierByIdentifierAlone() {
        let current = ScreenshotInboxSingleInstanceGuard.AppIdentity(
            processIdentifier: 10,
            bundleIdentifier: "com.example.ScreenshotInbox.debug",
            executableURL: URL(fileURLWithPath: "/tmp/ScreenshotInbox")
        )
        let release = ScreenshotInboxSingleInstanceGuard.AppIdentity(
            processIdentifier: 20,
            bundleIdentifier: "com.example.ScreenshotInbox",
            executableURL: URL(fileURLWithPath: "/Applications/Screenshot Inbox.app/Contents/MacOS/ScreenshotInbox")
        )

        #expect(!ScreenshotInboxSingleInstanceGuard.hasMatchingBundleIdentifier(current, release))
    }

    @Test
    func terminatesNewlyLaunchedDuplicateWhenCurrentDebugInstanceIsAlreadyRunning() {
        let current = ScreenshotInboxSingleInstanceGuard.AppIdentity(
            processIdentifier: 10,
            bundleIdentifier: "com.screenshotinbox.debug",
            executableURL: URL(fileURLWithPath: "/Applications/codes/screenshot_V2/.build/arm64-apple-macosx/debug/ScreenshotInbox")
        )
        let installed = ScreenshotInboxSingleInstanceGuard.AppIdentity(
            processIdentifier: 20,
            bundleIdentifier: "com.chihentai.screenshotinbox",
            executableURL: URL(fileURLWithPath: "/Applications/Screenshot Inbox.app/Contents/MacOS/ScreenshotInbox")
        )

        let action = ScreenshotInboxSingleInstanceGuard.actionForLaunchedApplication(
            current: current,
            launched: installed
        )

        #expect(action == .terminateLaunchedApplication)
    }
}
