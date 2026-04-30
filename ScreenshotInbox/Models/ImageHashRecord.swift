import Foundation

struct ImageHashRecord: Hashable {
    static let dHashAlgorithm = "dhash64"

    let screenshotUUID: String
    let algorithm: String
    let hash: String
    let createdAt: Date
}
