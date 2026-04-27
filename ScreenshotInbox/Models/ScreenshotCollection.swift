import Foundation

/// User-created collection (album) of screenshots.
struct ScreenshotCollection: Identifiable, Hashable {
    let id: UUID
    var name: String
    // TODO: parentID, ordering, color, smart-rule reference.
}
