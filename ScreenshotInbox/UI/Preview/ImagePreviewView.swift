import SwiftUI

/// Phase 5 mock Quick Look. Real implementation (`QLPreviewPanel` integration,
/// pan/zoom, multi-screenshot navigation) lands in a later phase. For now this
/// shows the existing `MockThumbnailView` enlarged inside a sheet so Space-key
/// preview has visible feedback.
struct ImagePreviewView: View {
    let screenshot: Screenshot
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            MockThumbnailView(kind: screenshot.thumbnailKind)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)

            footer
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 420, idealHeight: 540)
        .background(Theme.SemanticColor.panel)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(screenshot.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.label)
                    .lineLimit(1)
                Text(metaLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel.opacity(0.85))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close preview")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.SemanticColor.divider.opacity(0.45))
                .frame(height: 0.5)
        }
    }

    private var footer: some View {
        HStack {
            Text("Press Space or Esc to close")
                .font(.system(size: 11))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.SemanticColor.divider.opacity(0.45))
                .frame(height: 0.5)
        }
    }

    private var metaLine: String {
        let dims = "\(screenshot.pixelWidth) × \(screenshot.pixelHeight)"
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(screenshot.byteSize), countStyle: .file)
        return "\(dims) · \(screenshot.format) · \(size)"
    }
}
