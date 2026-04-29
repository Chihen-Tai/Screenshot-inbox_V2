import Foundation

struct OCRRecognitionResult {
    var text: String
    var language: String?
    var confidence: Double?
}

protocol OCRService {
    func recognizeText(for screenshot: Screenshot) async throws -> OCRRecognitionResult
}

enum OCRServiceError: Error {
    case missingImage
}
