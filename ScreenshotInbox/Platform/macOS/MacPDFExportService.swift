import Foundation
import CoreGraphics
import ImageIO

final class MacPDFExportService: PDFExporting {
    private let library: MacLibraryService
    private let fileManager: FileManager

    init(library: MacLibraryService, fileManager: FileManager = .default) {
        self.library = library
        self.fileManager = fileManager
    }

    func export(screenshots: [Screenshot], options: PDFExportOptions) async throws -> PDFExportResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            let ordered = self.orderedScreenshots(screenshots, order: options.order)
            guard !ordered.isEmpty else { throw PDFExportError.noScreenshots }
            let outputURL = URL(fileURLWithPath: options.outputPath)
            guard outputURL.pathExtension.lowercased() == "pdf" else {
                throw PDFExportError.invalidOutputPath
            }
            try self.fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let consumer = CGDataConsumer(url: outputURL as CFURL),
                  let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
                throw PDFExportError.cannotCreateContext
            }

            var pageCount = 0
            var skipped = 0
            for (index, screenshot) in ordered.enumerated() {
                guard let imageURL = self.imageURL(for: screenshot),
                      let image = self.loadCGImage(at: imageURL) else {
                    #if DEBUG
                    print("[PDFExport] screenshot uuid: \(screenshot.uuidString)")
                    print("[PDFExport] libraryPath: \(screenshot.libraryPath ?? "nil")")
                    print("[PDFExport] originalPath: unavailable")
                    print("[PDFExport] skipped missing/unreadable image: \(screenshot.libraryPath ?? screenshot.name)")
                    #endif
                    skipped += 1
                    continue
                }
                let imageSize = CGSize(width: image.width, height: image.height)
                guard self.isValidSize(imageSize) else {
                    #if DEBUG
                    print("[PDFExport] skipped invalid image size path=\(imageURL.path) size=\(self.debugSize(imageSize))")
                    #endif
                    skipped += 1
                    continue
                }

                let pageRect = self.safePageRect(for: imageSize, options: options)
                let margin = self.safeMargin(options.margins.points, for: pageRect)
                let contentRect = self.safeContentRect(pageRect: pageRect, margin: margin)
                let placement = self.imagePlacement(imageSize: imageSize, in: contentRect, fit: options.imageFit)
                let drawRect = placement.rect
                guard self.isValidRect(pageRect),
                      self.isValidRect(contentRect),
                      self.isValidRect(drawRect) else {
                    #if DEBUG
                    print("[PDFExport] skipped invalid geometry path=\(imageURL.path)")
                    print("[PDFExport] page: \(self.debugRect(pageRect))")
                    print("[PDFExport] available: \(self.debugRect(contentRect))")
                    print("[PDFExport] drawRect: \(self.debugRect(drawRect))")
                    #endif
                    skipped += 1
                    continue
                }

                guard self.isSafeNoCropPlacement(drawRect: drawRect, contentRect: contentRect, fit: options.imageFit) else {
                    #if DEBUG
                    print("[PDFExport] skipped crop-risk geometry path=\(imageURL.path)")
                    print("[PDFExport] available: \(self.debugRect(contentRect))")
                    print("[PDFExport] drawRect: \(self.debugRect(drawRect))")
                    #endif
                    skipped += 1
                    continue
                }

                #if DEBUG
                self.writeDebugSourceCopy(from: imageURL, pageIndex: index + 1)
                #endif

                context.beginPDFPage(self.pageInfoDictionary(mediaBox: pageRect))
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(pageRect)
                #if DEBUG
                print("[PDFExport] screenshot uuid: \(screenshot.uuidString)")
                print("[PDFExport] libraryPath: \(screenshot.libraryPath ?? "nil")")
                print("[PDFExport] originalPath: unavailable")
                print("[PDFExport] image source used: managed library original")
                print("[PDFExport] image path: \(imageURL.path)")
                print("[PDFExport] loaded image pixel size: \(self.debugSize(imageSize))")
                print("[PDFExport] page mode: \(options.pageSize.rawValue)")
                print("[PDFExport] resolved page: \(self.debugSize(pageRect.size))")
                print("[PDFExport] orientation: \(options.orientation.rawValue)")
                print("[PDFExport] margin: \(self.safeNumber(margin))")
                print("[PDFExport] available: \(self.debugRect(contentRect))")
                print("[PDFExport] drawRect: \(self.debugRect(drawRect))")
                print("[PDFExport] scale: \(self.safeNumber(placement.scale))")
                print("[PDFExport] imageFit: \(options.imageFit.rawValue)")
                #endif
                context.draw(image, in: drawRect)
                context.endPDFPage()
                pageCount += 1
            }
            context.closePDF()
            guard pageCount > 0 else { throw PDFExportError.noRenderableImages }
            let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            return PDFExportResult(
                outputPath: outputURL.path,
                pageCount: pageCount,
                fileSize: size,
                createdAt: Date(),
                skippedCount: skipped
            )
        }.value
    }

    private func orderedScreenshots(_ screenshots: [Screenshot], order: PDFExportOrder) -> [Screenshot] {
        switch order {
        case .currentGridOrder:
            return screenshots
        case .dateAscending:
            return screenshots.sorted { $0.createdAt < $1.createdAt }
        case .dateDescending:
            return screenshots.sorted { $0.createdAt > $1.createdAt }
        case .filenameAscending:
            return screenshots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .filenameDescending:
            return screenshots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        }
    }

    private func imageURL(for screenshot: Screenshot) -> URL? {
        guard let libraryPath = screenshot.libraryPath else { return nil }
        if libraryPath.hasPrefix("/") {
            return URL(fileURLWithPath: libraryPath)
        }
        return library.libraryRootURL.appendingPathComponent(libraryPath)
    }

    private func loadCGImage(at url: URL) -> CGImage? {
        guard fileManager.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func safePageRect(for imageSize: CGSize, options: PDFExportOptions) -> CGRect {
        let fallback = CGSize(width: 595, height: 842)
        let size: CGSize
        switch options.pageSize {
        case .auto:
            size = autoPageSize(for: imageSize, orientation: options.orientation)
        case .originalImageSize:
            size = originalImagePageSize(for: imageSize, orientation: options.orientation)
        case .a4:
            size = fixedPageSize(width: 595, height: 842, imageSize: imageSize, orientation: options.orientation)
        case .letter:
            size = fixedPageSize(width: 612, height: 792, imageSize: imageSize, orientation: options.orientation)
        }
        return CGRect(origin: .zero, size: isValidSize(size) ? size : fallback)
    }

    private func fixedPageSize(width: CGFloat, height: CGFloat, imageSize: CGSize, orientation: PDFOrientation) -> CGSize {
        switch orientation {
        case .portrait:
            return CGSize(width: min(width, height), height: max(width, height))
        case .landscape:
            return CGSize(width: max(width, height), height: min(width, height))
        case .auto:
            return imageSize.width > imageSize.height
                ? CGSize(width: max(width, height), height: min(width, height))
                : CGSize(width: min(width, height), height: max(width, height))
        }
    }

    private func autoPageSize(for imageSize: CGSize, orientation: PDFOrientation) -> CGSize {
        guard isValidSize(imageSize) else { return CGSize(width: 595, height: 842) }
        let targetOrientation: PDFOrientation
        switch orientation {
        case .auto:
            targetOrientation = imageSize.width >= imageSize.height ? .landscape : .portrait
        default:
            targetOrientation = orientation
        }

        let maxLongSide: CGFloat = 842
        let minShortSide: CGFloat = 320
        let aspect = imageSize.width / imageSize.height
        let landscape = targetOrientation == .landscape
        var width: CGFloat
        var height: CGFloat

        if landscape {
            width = maxLongSide
            height = width / aspect
            if height < minShortSide {
                height = minShortSide
            }
            if height > maxLongSide {
                height = maxLongSide
                width = height * aspect
            }
        } else {
            height = maxLongSide
            width = height * aspect
            if width < minShortSide {
                width = minShortSide
            }
            if width > maxLongSide {
                width = maxLongSide
                height = width / aspect
            }
        }

        return CGSize(width: width, height: height)
    }

    private func originalImagePageSize(for imageSize: CGSize, orientation: PDFOrientation) -> CGSize {
        guard isValidSize(imageSize) else { return CGSize(width: 595, height: 842) }
        let maxDimension: CGFloat = 1440
        let scale = min(1, maxDimension / max(imageSize.width, imageSize.height))
        var size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        switch orientation {
        case .portrait where size.width > size.height:
            size = CGSize(width: size.height, height: size.width)
        case .landscape where size.height > size.width:
            size = CGSize(width: size.height, height: size.width)
        default:
            break
        }
        return size
    }

    private func imagePlacement(imageSize: CGSize, in contentRect: CGRect, fit: PDFImageFit) -> (rect: CGRect, scale: CGFloat) {
        guard isValidSize(imageSize), isValidRect(contentRect) else {
            return (.null, 0)
        }

        switch fit {
        case .fit:
            return fittedImagePlacement(imageSize: imageSize, in: contentRect)
        case .fill:
            return filledImagePlacement(imageSize: imageSize, in: contentRect)
        }
    }

    private func pageInfoDictionary(mediaBox: CGRect) -> CFDictionary {
        var box = mediaBox
        let data = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
        return [kCGPDFContextMediaBox as String: data] as CFDictionary
    }

    private func fittedImagePlacement(imageSize: CGSize, in availableRect: CGRect) -> (rect: CGRect, scale: CGFloat) {
        guard isValidSize(imageSize), isValidRect(availableRect) else { return (.null, 0) }
        let scale = min(
            availableRect.width / imageSize.width,
            availableRect.height / imageSize.height
        )
        guard scale.isFinite, scale > 0 else { return (.null, 0) }

        let drawWidth = imageSize.width * scale
        let drawHeight = imageSize.height * scale

        let rect = CGRect(
            x: availableRect.midX - drawWidth / 2,
            y: availableRect.midY - drawHeight / 2,
            width: drawWidth,
            height: drawHeight
        )
        return (rect.intersection(availableRect), scale)
    }

    private func filledImagePlacement(imageSize: CGSize, in availableRect: CGRect) -> (rect: CGRect, scale: CGFloat) {
        guard isValidSize(imageSize), isValidRect(availableRect) else { return (.null, 0) }
        let imageAspect = imageSize.width / imageSize.height
        let availableAspect = availableRect.width / availableRect.height
        let drawWidth: CGFloat
        let drawHeight: CGFloat

        if imageAspect > availableAspect {
            drawHeight = availableRect.height
            drawWidth = drawHeight * imageAspect
        } else {
            drawWidth = availableRect.width
            drawHeight = drawWidth / imageAspect
        }

        let rect = CGRect(
            x: availableRect.midX - drawWidth / 2,
            y: availableRect.midY - drawHeight / 2,
            width: drawWidth,
            height: drawHeight
        )
        return (rect, drawWidth / imageSize.width)
    }

    private func safeMargin(_ rawMargin: Double, for pageRect: CGRect) -> CGFloat {
        guard rawMargin.isFinite, rawMargin >= 0, isValidRect(pageRect) else { return 0 }
        let margin = CGFloat(rawMargin)
        let maxMargin = min(pageRect.width, pageRect.height) / 2 - 1
        return min(max(0, margin), max(0, maxMargin))
    }

    private func safeContentRect(pageRect: CGRect, margin: CGFloat) -> CGRect {
        guard isValidRect(pageRect), margin.isFinite, margin >= 0 else { return .null }
        let contentRect = pageRect.insetBy(dx: margin, dy: margin)
        return isValidRect(contentRect) ? contentRect : pageRect
    }

    private func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private func isValidRect(_ rect: CGRect) -> Bool {
        !rect.isNull &&
        rect.origin.x.isFinite &&
        rect.origin.y.isFinite &&
        rect.width.isFinite &&
        rect.height.isFinite &&
        rect.width > 0 &&
        rect.height > 0
    }

    private func isSafeNoCropPlacement(drawRect: CGRect, contentRect: CGRect, fit: PDFImageFit) -> Bool {
        guard fit == .fit else { return true }
        guard isValidRect(drawRect), isValidRect(contentRect) else { return false }
        let epsilon: CGFloat = 0.5
        return drawRect.width <= contentRect.width + epsilon &&
            drawRect.height <= contentRect.height + epsilon &&
            drawRect.minX >= contentRect.minX - epsilon &&
            drawRect.maxX <= contentRect.maxX + epsilon &&
            drawRect.minY >= contentRect.minY - epsilon &&
            drawRect.maxY <= contentRect.maxY + epsilon
    }

    #if DEBUG
    private func writeDebugSourceCopy(from sourceURL: URL, pageIndex: Int) {
        let debugFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFExportDebug", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: debugFolder, withIntermediateDirectories: true)
            let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
            let destination = debugFolder.appendingPathComponent(
                String(format: "page-%02d-source.%@", pageIndex, ext)
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            print("[PDFExport] debug source copy: \(destination.path)")
        } catch {
            print("[PDFExport] debug source copy failed: \(error)")
        }
    }

    private func safeNumber(_ value: CGFloat) -> String {
        guard value.isFinite else { return "invalid(\(value))" }
        return String(format: "%.1f", Double(value))
    }

    private func debugSize(_ size: CGSize) -> String {
        "\(safeNumber(size.width))x\(safeNumber(size.height))"
    }

    private func debugRect(_ rect: CGRect) -> String {
        "x=\(safeNumber(rect.origin.x)) y=\(safeNumber(rect.origin.y)) w=\(safeNumber(rect.width)) h=\(safeNumber(rect.height))"
    }
    #endif
}
