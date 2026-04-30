import Foundation

enum AppPrivacyInfo {
    static let localFirstGuarantee = "Screenshot Inbox is local-first. It does not upload your screenshots or OCR text to any server."
    static let noTelemetryStatement = "No telemetry or network services are included."
    static let watchedFoldersStatement = "Only configured watched folders are monitored."
    static let originalSourceSafetyStatement = "Original source files are not modified by default."
    static let managedLibraryDescription = "The managed library stores imported originals, thumbnails, OCR text, detected QR/code payloads, tags, collections, and the SQLite database locally on this Mac."
    static let sandboxStatus = "GitHub builds are currently non-sandboxed. Sandbox support is deferred so file watching and import workflows keep working while folder-access boundaries are prepared."
}
