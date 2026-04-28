import Foundation

struct Tag: Identifiable, Hashable {
    var id: Int?
    var uuid: String
    var name: String
    var color: String?
    var createdAt: Date
    var updatedAt: Date?
}
