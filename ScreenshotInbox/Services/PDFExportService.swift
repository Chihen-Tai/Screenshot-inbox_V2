import Foundation

protocol PDFExporting {
    func export(screenshots: [Screenshot], options: PDFExportOptions) async throws -> PDFExportResult
}

enum PDFExportError: Error {
    case noScreenshots
    case noRenderableImages
    case invalidOutputPath
    case cannotCreateContext
}
