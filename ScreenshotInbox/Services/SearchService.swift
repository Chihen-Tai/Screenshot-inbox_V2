import Foundation

final class SearchService {
    init() {}

    func filter(
        _ screenshots: [Screenshot],
        query: String,
        collectionNamesByScreenshotID: [UUID: [String]] = [:],
        detectedCodesByScreenshotID: [String: [DetectedCode]] = [:]
    ) -> [Screenshot] {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
        guard !tokens.isEmpty else { return screenshots }
        return screenshots.filter { screenshot in
            let searchable = [
                screenshot.name,
                screenshot.format,
                screenshot.tags.joined(separator: " "),
                screenshot.ocrSnippets.joined(separator: " "),
                collectionNamesByScreenshotID[screenshot.id, default: []].joined(separator: " "),
                detectedCodesByScreenshotID[screenshot.uuidString, default: []].map(\.payload).joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            return tokens.allSatisfy { searchable.contains($0) }
        }
    }
}
