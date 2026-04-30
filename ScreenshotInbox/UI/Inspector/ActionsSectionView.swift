import SwiftUI

struct ActionsSectionView: View {
    @EnvironmentObject private var appState: AppState
    let screenshot: Screenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Actions")
            VStack(spacing: 0) {
                ActionRow(title: "Open",
                          systemImage: "arrow.up.right.square") {
                    appState.router.open([screenshot])
                }
                rowDivider
                ActionRow(title: "Reveal in Finder",
                          systemImage: "magnifyingglass") {
                    appState.router.revealInFinder([screenshot])
                }
                rowDivider
                if screenshot.isTrashed {
                    ActionRow(title: "Restore",
                              systemImage: "arrow.uturn.backward") {
                        appState.router.restoreFromTrash([screenshot])
                    }
                    rowDivider
                    ActionRow(title: "Delete Permanently",
                              systemImage: "trash.slash",
                              isDestructive: true) {
                        appState.router.deletePermanently([screenshot])
                    }
                } else {
                    ActionRow(title: screenshot.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                              systemImage: screenshot.isFavorite ? "star.slash" : "star") {
                        appState.router.toggleFavorite([screenshot])
                    }
                    rowDivider
                    ActionRow(title: "Quick Look",
                              systemImage: "eye") {
                        appState.router.quickLook([screenshot])
                    }
                    rowDivider
                    ActionRow(title: "Rename",
                              systemImage: "pencil") {
                        appState.router.rename(screenshot)
                    }
                    rowDivider
                    ActionRow(title: "Add Tag",
                              systemImage: "tag") {
                        appState.router.addTag([screenshot])
                    }
                    rowDivider
                    ActionRow(title: "Add to Collection",
                              systemImage: "folder") {
                        appState.router.moveToCollection([screenshot])
                    }
                    rowDivider
                    ActionRow(title: "Export as PDF",
                              systemImage: "doc.richtext") {
                        appState.router.mergeIntoPDF([screenshot])
                    }
                    rowDivider
                    ActionRow(title: "Export Original",
                              systemImage: "square.and.arrow.up") {
                        appState.router.exportOriginals([screenshot])
                    }
                    rowDivider
                    ActionRow(title: "Copy Image",
                              systemImage: "doc.on.clipboard") {
                        appState.router.copyImage([screenshot])
                    }
                    rowDivider
                    ActionRow(title: "Move to Trash",
                              systemImage: "trash",
                              isDestructive: true) {
                        appState.router.moveToTrash([screenshot])
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Theme.SemanticColor.quietFill.opacity(0.35))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.SemanticColor.divider.opacity(0.35))
            .frame(height: 0.5)
            .padding(.leading, 36)
    }
}

private struct ActionRow: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(textColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                isHovering
                    ? Theme.SemanticColor.label.opacity(0.05)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
    }

    private var iconColor: Color {
        isDestructive ? Color.red.opacity(0.65) : Theme.SemanticColor.secondaryLabel
    }
    private var textColor: Color {
        isDestructive ? Color.red.opacity(0.78) : Theme.SemanticColor.label
    }
}
