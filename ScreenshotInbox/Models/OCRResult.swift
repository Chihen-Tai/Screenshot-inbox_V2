import Foundation

enum OCRStatus: String, Hashable {
    case pending
    case processing
    case complete
    case failed
    case skipped
}

struct OCRResult: Hashable {
    var id: Int?
    var screenshotUUID: String
    var text: String?
    var language: String?
    var confidence: Double?
    var status: OCRStatus
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date?
}
