import Foundation

enum PDFPageSize: String, CaseIterable, Hashable {
    case auto
    case originalImageSize
    case a4
    case letter

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .originalImageSize: return "Original Image Size"
        case .a4: return "A4"
        case .letter: return "Letter"
        }
    }
}

enum PDFOrientation: String, CaseIterable, Hashable {
    case auto
    case portrait
    case landscape

    var title: String { rawValue.capitalized }
}

enum PDFMargin: String, CaseIterable, Hashable {
    case none
    case small
    case medium

    var title: String { rawValue.capitalized }

    var points: Double {
        switch self {
        case .none: return 0
        case .small: return 24
        case .medium: return 48
        }
    }
}

enum PDFImageFit: String, CaseIterable, Hashable {
    case fit
    case fill

    var title: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        }
    }
}

enum PDFExportOrder: String, CaseIterable, Hashable {
    case currentGridOrder
    case dateAscending
    case dateDescending
    case filenameAscending
    case filenameDescending

    var title: String {
        switch self {
        case .currentGridOrder: return "Current Grid Order"
        case .dateAscending: return "Date Ascending"
        case .dateDescending: return "Date Descending"
        case .filenameAscending: return "Filename A-Z"
        case .filenameDescending: return "Filename Z-A"
        }
    }
}

struct PDFExportOptions: Hashable {
    var pageSize: PDFPageSize
    var orientation: PDFOrientation
    var margins: PDFMargin
    var imageFit: PDFImageFit
    var order: PDFExportOrder
    var outputPath: String
    var addBackToLibrary: Bool

    static func defaults(outputPath: String) -> PDFExportOptions {
        PDFExportOptions(
            pageSize: .auto,
            orientation: .auto,
            margins: .small,
            imageFit: .fit,
            order: .currentGridOrder,
            outputPath: outputPath,
            addBackToLibrary: false
        )
    }
}

struct PDFExportResult: Hashable {
    var outputPath: String
    var pageCount: Int
    var fileSize: Int?
    var createdAt: Date
    var skippedCount: Int
}
