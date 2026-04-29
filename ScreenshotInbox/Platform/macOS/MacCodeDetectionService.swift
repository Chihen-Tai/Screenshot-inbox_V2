import Foundation
import Vision

final class MacCodeDetectionService: CodeDetectionService {
    private let library: MacLibraryService
    private let fileManager: FileManager

    init(library: MacLibraryService, fileManager: FileManager = .default) {
        self.library = library
        self.fileManager = fileManager
    }

    func detectCodes(for screenshot: Screenshot) async throws -> [CodeDetectionResult] {
        let imageURL = try imageURL(for: screenshot)
        return try await Task.detached(priority: .utility) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = Self.supportedSymbologies(for: request)
            #if DEBUG
            print("[CodeDetection] input image path: \(imageURL.path)")
            print("[CodeDetection] symbologies: \(request.symbologies.map(\.rawValue).joined(separator: ", "))")
            #endif

            let handler = VNImageRequestHandler(url: imageURL, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            var seen: Set<String> = []
            let results = observations.compactMap { observation -> CodeDetectionResult? in
                guard let payload = observation.payloadStringValue,
                      !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let key = "\(observation.symbology.rawValue)\n\(payload)"
                guard seen.insert(key).inserted else { return nil }
                return CodeDetectionResult(
                    symbology: Self.displayName(for: observation.symbology),
                    payload: payload,
                    isURL: Self.isOpenableURL(payload)
                )
            }
            #if DEBUG
            print("[CodeDetection] result count: \(results.count)")
            #endif
            return results
        }.value
    }

    private static func supportedSymbologies(for request: VNDetectBarcodesRequest) -> [VNBarcodeSymbology] {
        let desired: [VNBarcodeSymbology] = [.qr, .aztec, .pdf417, .ean13, .code128]
        if #available(macOS 12.0, *) {
            let supported = Set(VNDetectBarcodesRequest.supportedSymbologies)
            let filtered = desired.filter { supported.contains($0) }
            return filtered.isEmpty ? [.qr] : filtered
        }
        return [.qr]
    }

    private static func displayName(for symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .qr: return "QR Code"
        case .aztec: return "Aztec"
        case .pdf417: return "PDF417"
        case .ean13: return "EAN-13"
        case .code128: return "Code 128"
        default: return symbology.rawValue
        }
    }

    private static func isOpenableURL(_ payload: String) -> Bool {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "mailto", "tel"].contains(scheme)
    }

    private func imageURL(for screenshot: Screenshot) throws -> URL {
        if let libraryPath = screenshot.libraryPath {
            let originalURL = library.libraryRootURL.appendingPathComponent(libraryPath)
            if fileManager.fileExists(atPath: originalURL.path) {
                return originalURL
            }
        }
        throw CodeDetectionServiceError.missingImage
    }
}
