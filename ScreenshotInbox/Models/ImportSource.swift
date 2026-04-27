import Foundation

/// A folder watched for new screenshots (e.g. ~/Desktop or ~/Pictures/Screenshots).
struct ImportSource: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var folderURL: URL
    var isEnabled: Bool
    // TODO: security-scoped bookmark data, last scan timestamp, filename pattern.
}
