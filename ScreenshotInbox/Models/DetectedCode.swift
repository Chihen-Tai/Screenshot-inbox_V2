import Foundation

struct DetectedCode: Identifiable, Hashable {
    var id: Int?
    var screenshotUUID: String
    var symbology: String
    var payload: String
    var isURL: Bool
    var createdAt: Date
    var updatedAt: Date?
}
