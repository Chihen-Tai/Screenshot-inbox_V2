import SwiftUI
import AppKit

struct ScreenshotGridItemView: View {
    let screenshot: Screenshot
    let isSelected: Bool
    let onSelect: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MockThumbnailView(kind: screenshot.thumbnailKind)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(screenshot.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if screenshot.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.yellow.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    Text(screenshot.format)
                    Text("·").foregroundStyle(.tertiary)
                    Text(humanFileSize(screenshot.byteSize))
                    if screenshot.isOCRComplete {
                        Text("·").foregroundStyle(.tertiary)
                        Text("OCR")
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isSelected ? Theme.Palette.selectionFill : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isSelected ? Theme.Palette.selectionStroke.opacity(0.55) : Color.clear,
                              lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let mods = NSEvent.modifierFlags
            let additive = mods.contains(.command) || mods.contains(.shift)
            onSelect(additive)
        }
    }

    private func humanFileSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
