import AppKit
import SwiftUI

struct ImagePreviewView: View {
    let screenshot: Screenshot
    let thumbnailProvider: MacThumbnailProvider?
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var mode: PreviewZoomMode = .fit
    @State private var customScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            imageSurface
            Divider().opacity(0.45)
            footer
        }
        .frame(minWidth: 760, idealWidth: 980, minHeight: 560, idealHeight: 720)
        .background(Theme.SemanticColor.panel)
        .onChange(of: screenshot.id) { _, _ in
            mode = .fit
            customScale = 1
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                appState.previewPrevious()
            case .right:
                appState.previewNext()
            default:
                break
            }
        }
        .onExitCommand {
            onClose()
        }
        .focusable()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: { appState.previewPrevious() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!appState.canPreviewPrevious)
            .help("Previous")

            Button(action: { appState.previewNext() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!appState.canPreviewNext)
            .help("Next")

            VStack(alignment: .leading, spacing: 2) {
                Text(screenshot.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.label)
                    .lineLimit(1)
                Text([appState.previewIndexText, metaLine].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom Out")

            Button(action: { mode = .fit }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Fit to Window")

            Button(action: { mode = .actualSize }) {
                Image(systemName: "1.magnifyingglass")
            }
            .keyboardShortcut("1", modifiers: .command)
            .help("Actual Size")

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .keyboardShortcut("+", modifiers: .command)
            .help("Zoom In")

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .foregroundStyle(Theme.SemanticColor.secondaryLabel.opacity(0.85))
            .accessibilityLabel("Close preview")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var imageSurface: some View {
        GeometryReader { proxy in
            if let image = thumbnailProvider?.loadPreviewImage(for: screenshot) {
                ZoomingImage(image: image, mode: mode, customScale: customScale, viewport: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    Text("Original image not found")
                        .font(.system(size: 14, weight: .medium))
                    Text("The managed library file is missing. You can still navigate to another screenshot.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                appState.router.toggleFavorite([screenshot])
            } label: {
                Label(screenshot.isFavorite ? "Unfavorite" : "Favorite",
                      systemImage: screenshot.isFavorite ? "star.fill" : "star")
            }

            Button {
                appState.router.revealInFinder([screenshot])
            } label: {
                Label("Reveal", systemImage: "folder")
            }

            Button {
                appState.router.copyOCRText([screenshot])
            } label: {
                Label("Copy OCR", systemImage: "doc.on.doc")
            }
            .disabled(!(screenshot.isOCRComplete && !screenshot.ocrSnippets.isEmpty))

            Button {
                appState.router.openDetectedLink([screenshot])
            } label: {
                Label("Open Link", systemImage: "link")
            }
            .disabled(!appState.detectedCodes(for: screenshot).contains(where: \.isURL))

            Button {
                appState.router.share([screenshot])
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                appState.router.moveToTrash([screenshot])
                appState.advancePreviewAfterRemovingCurrent()
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var metaLine: String {
        let dims = "\(screenshot.pixelWidth) x \(screenshot.pixelHeight)"
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(screenshot.byteSize),
            countStyle: .file
        )
        return "\(dims) · \(screenshot.format) · \(size)"
    }

    private func zoomIn() {
        customScale = min(currentScale * 1.25, 6)
        mode = .custom
    }

    private func zoomOut() {
        customScale = max(currentScale / 1.25, 0.1)
        mode = .custom
    }

    private var currentScale: CGFloat {
        switch mode {
        case .fit:
            return 1
        case .actualSize:
            return 1
        case .custom:
            return customScale
        }
    }
}

private enum PreviewZoomMode: Equatable {
    case fit
    case actualSize
    case custom
}

private struct ZoomingImage: View {
    let image: NSImage
    let mode: PreviewZoomMode
    let customScale: CGFloat
    let viewport: CGSize

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: displaySize.width, height: displaySize.height)
                .frame(
                    minWidth: viewport.width,
                    minHeight: viewport.height,
                    alignment: .center
                )
        }
    }

    private var displaySize: CGSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return viewport
        }
        switch mode {
        case .fit:
            let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
            let boundedScale = min(max(scale, 0.01), 1)
            return CGSize(width: imageSize.width * boundedScale, height: imageSize.height * boundedScale)
        case .actualSize:
            return imageSize
        case .custom:
            return CGSize(width: imageSize.width * customScale, height: imageSize.height * customScale)
        }
    }
}
