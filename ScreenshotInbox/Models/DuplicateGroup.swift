import Foundation

enum DuplicateGroupKind: String, Hashable {
    case exact
    case similar

    var displayName: String {
        switch self {
        case .exact: return "Exact Duplicate"
        case .similar: return "Similar"
        }
    }
}

struct DuplicateGroup: Identifiable, Hashable {
    let id: String
    let kind: DuplicateGroupKind
    let screenshotUUIDs: [String]
    let confidence: Double
    let createdAt: Date?
    let recommendedKeepUUID: String?
}
