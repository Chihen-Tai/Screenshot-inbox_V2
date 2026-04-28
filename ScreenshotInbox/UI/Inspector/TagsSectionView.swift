import SwiftUI

struct TagsSectionView: View {
    @EnvironmentObject private var appState: AppState
    let screenshot: Screenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Tags")
                Spacer(minLength: 0)
                Button {
                    appState.router.addTag([screenshot])
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Add Tag")
            }
            if screenshot.tags.isEmpty {
                Text("No tags")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(screenshot.tags, id: \.self) { tag in
                        TagPill(text: tag)
                    }
                }
            }
        }
    }
}

private struct TagPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Theme.Palette.accent.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(Theme.Palette.accent.opacity(0.20), lineWidth: 0.5)
            )
            .foregroundStyle(Theme.Palette.accent.opacity(0.95))
    }
}
