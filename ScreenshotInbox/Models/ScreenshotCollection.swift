import Foundation

/// User-created collection (album) of screenshots.
struct ScreenshotCollection: Identifiable, Hashable {
    var id: Int?
    var uuid: String
    var name: String
    var type: String
    var sortIndex: Double
    var createdAt: Date
    var updatedAt: Date?
}
