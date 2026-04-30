import Testing
@testable import ScreenshotInbox

struct ReleaseReadinessTests {
    @Test
    func releaseMetadataMatchesAlphaRelease() {
        #expect(AppReleaseInfo.name == "Screenshot Inbox")
        #expect(AppReleaseInfo.version == "0.1.0-alpha")
        #expect(AppReleaseInfo.build == "1")
        #expect(AppReleaseInfo.copyright == "Copyright © 2026 Chihen Tai")
        #expect(AppReleaseInfo.license == "MIT")
        #expect(AppReleaseInfo.shortDescription == "A local-first macOS screenshot organizer.")
        #expect(AppReleaseInfo.privacyNote == "Local-first. No account required.")
    }

    @Test
    func onboardingPreferenceKeyIsStable() {
        #expect(FirstRunOnboarding.preferenceKey == "ScreenshotInbox.hasSeenOnboarding")
    }
}
