import Foundation

enum AppReleaseInfo {
    static let name = "Screenshot Inbox"
    static let executableName = "ScreenshotInbox"
    static let bundleIdentifier = "com.chihentai.screenshotinbox"
    static let version = "0.1.0-alpha"
    static let build = "1"
    static let copyright = "Copyright © 2026 Chihen Tai"
    static let license = "MIT"
    static let shortDescription = "A local-first macOS screenshot organizer."
    static let privacyNote = "Local-first. No account required."
    static let repositoryPlaceholder = "https://github.com/<your-username>/ScreenshotInbox"
}

enum FirstRunOnboarding {
    static let preferenceKey = "ScreenshotInbox.hasSeenOnboarding"
}
