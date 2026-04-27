import Foundation

/// Vision OCR output for a screenshot.
struct OCRResult: Hashable {
    let screenshotID: UUID
    var text: String
    var confidence: Double
    // TODO: per-region observations with bounding boxes.
}
