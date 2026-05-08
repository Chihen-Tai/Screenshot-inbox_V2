import SwiftUI

struct ScreenshotInboxGridItemView: View {
    let item: ScreenshotItem
    let isSelected: Bool
    let copyAction: () -> Void
    let revealAction: () -> Void
    let openAction: () -> Void
    let dismissAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ScreenshotInboxThumbnail(url: item.url)
                    .frame(height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(borderColor, lineWidth: isSelected || item.isNew ? 1.5 : 1)
                    )

                if item.isNew && !item.isDismissed {
                    Text("NEW")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(8)
                }
            }
            .onDrag { dragProvider(for: item.url) }

            Text(item.url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)

            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 236, alignment: .topLeading)
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            Button("Copy", action: copyAction)
            Button("Reveal in Finder", action: revealAction)
            Button("Open", action: openAction)
            Button("Dismiss", action: dismissAction)
            Divider()
            Button("Delete File...", role: .destructive, action: deleteAction)
        }
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if item.isNew && !item.isDismissed { return .accentColor.opacity(0.7) }
        return .secondary.opacity(0.25)
    }

    private func dragProvider(for url: URL) -> NSItemProvider {
        NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
    }
}

struct ScreenshotInboxThumbnail: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
