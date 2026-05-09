import Foundation

enum AppReleaseInfo {
    static let name = "Screenshot Inbox"
    static let executableName = "ScreenshotInbox"
    static let bundleIdentifier = "com.chihentai.screenshotinbox"
    static let version = "0.4.0-alpha"
    static let build = "4"
    static let copyright = "Copyright © 2026 Chihen Tai"
    static let license = "MIT"
    static let shortDescription = "A local-first macOS screenshot organizer."
    static let privacyNote = "Local-first. No account required."
    static let repositoryURL = "https://github.com/Chihen-Tai/Screenshot-inbox_V2"
    static let repositoryIssuesURL = "https://github.com/Chihen-Tai/Screenshot-inbox_V2/issues"
    static let repositoryPlaceholder = repositoryURL
}

enum FirstRunOnboarding {
    static let preferenceKey = "ScreenshotInbox.hasSeenOnboarding"
}
