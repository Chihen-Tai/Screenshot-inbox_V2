import SwiftUI

struct MetadataSectionView: View {
    let screenshot: Screenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Metadata")
            VStack(alignment: .leading, spacing: 7) {
                row("Name",      screenshot.name)
                row("Size",      "\(screenshot.pixelWidth) × \(screenshot.pixelHeight)")
                row("Format",    screenshot.format)
                row("File Size", humanSize(screenshot.byteSize))
                row("Created",   Self.dateFormatter.string(from: screenshot.createdAt))
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                .frame(width: Theme.Layout.metadataLabelWidth, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.SemanticColor.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func humanSize(_ b: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
