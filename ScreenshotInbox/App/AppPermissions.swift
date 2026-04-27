import Foundation

/// Centralizes macOS permission flows.
/// Phase 2 will request folder access via NSOpenPanel + security-scoped bookmarks
/// and surface state to the UI through SettingsService.
enum AppPermissions {
    // TODO: static func requestScreenshotsFolderAccess() async -> Bool
    // TODO: static func hasAccess(to url: URL) -> Bool
}
