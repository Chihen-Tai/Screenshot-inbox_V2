import Foundation
import Vision

final class MacOCRService: OCRService {
    private let library: MacLibraryService
    private let fileManager: FileManager
    private let preferredLanguagesProvider: () -> [String]

    init(
        library: MacLibraryService,
        fileManager: FileManager = .default,
        preferredLanguagesProvider: @escaping () -> [String] = { ["zh-Hant", "zh-Hans", "en-US"] }
    ) {
        self.library = library
        self.fileManager = fileManager
        self.preferredLanguagesProvider = preferredLanguagesProvider
    }

    func recognizeText(for screenshot: Screenshot) async throws -> OCRRecognitionResult {
        let imageURL = try imageURL(for: screenshot)
        let preferredLanguages = preferredLanguagesProvider()
        return try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = Self.preferredRecognitionLanguages(
                for: request,
                desired: preferredLanguages
            )
            #if DEBUG
            print("[OCR] input image path: \(imageURL.path)")
            print("[OCR] recognition languages: \(request.recognitionLanguages.joined(separator: ", "))")
            print("[OCR] recognitionLevel: accurate")
            #endif

            let handler = VNImageRequestHandler(url: imageURL, options: [:])
            do {
                try handler.perform([request])
            } catch {
                #if DEBUG
                print("[OCR] failed error: \(error)")
                #endif
                throw error
            }

            let observations = request.results ?? []
            var lines: [String] = []
            var confidences: [Float] = []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                lines.append(candidate.string)
                confidences.append(candidate.confidence)
            }
            let text = lines.joined(separator: "\n")
            let confidence = confidences.isEmpty
                ? nil
                : Double(confidences.reduce(0, +)) / Double(confidences.count)
            #if DEBUG
            print("[OCR] result length: \(text.count)")
            #endif
            return OCRRecognitionResult(text: text, language: nil, confidence: confidence)
        }.value
    }

    private static func preferredRecognitionLanguages(for request: VNRecognizeTextRequest, desired: [String]) -> [String] {
        let desired = desired.isEmpty ? ["zh-Hant", "zh-Hans", "en-US"] : desired
        do {
            let supported: [String]
            if #available(macOS 12.0, *) {
                supported = try request.supportedRecognitionLanguages()
            } else {
                supported = try VNRecognizeTextRequest.supportedRecognitionLanguages(
                    for: request.recognitionLevel,
                    revision: request.revision
                )
            }
            let filtered = desired.filter { supported.contains($0) }
            return filtered.isEmpty ? desired : filtered
        } catch {
            #if DEBUG
            print("[OCR] supported language query failed: \(error)")
            #endif
            return desired
        }
    }

    private func imageURL(for screenshot: Screenshot) throws -> URL {
        if let libraryPath = screenshot.libraryPath {
            let originalURL = library.libraryRootURL.appendingPathComponent(libraryPath)
            if fileManager.fileExists(atPath: originalURL.path) {
                return originalURL
            }
        }
        let largeThumbnailURL = library.largeThumbnailURL(for: screenshot.id)
        if fileManager.fileExists(atPath: largeThumbnailURL.path) {
            return largeThumbnailURL
        }
        throw OCRServiceError.missingImage
    }
}
