import Foundation

struct CodeDetectionResult: Hashable {
    var symbology: String
    var payload: String
    var isURL: Bool
}

protocol CodeDetectionService {
    func detectCodes(for screenshot: Screenshot) async throws -> [CodeDetectionResult]
}

enum CodeDetectionServiceError: Error {
    case missingImage
}
