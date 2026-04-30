import SwiftUI

/// Floating toolbar shown at the bottom of the grid when 2+ screenshots
/// are selected.
///
/// Phase 4: visuals only. Buttons surface intent ("Add Tag", "Move",
/// "Merge PDF", "Trash") but do not perform any actions yet.
struct BatchActionBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < Theme.Layout.batchBarCompactBreakpoint
            HStack(spacing: 10) {
                Text("\(appState.selection.count) selected")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    .padding(.trailing, 4)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                if appState.sidebarSelection == .trash {
                    BatchButton(title: "Restore",
                                systemImage: "arrow.uturn.backward",
                                action: { appState.router.restoreFromTrash(appState.selectedScreenshots) })
                    BatchButton(title: isCompact ? "Delete" : "Delete Permanently",
                                systemImage: "trash.slash",
                                style: .destructive,
                                action: { appState.router.deletePermanently(appState.selectedScreenshots) })
                    BatchButton(title: isCompact ? "Clear" : "Clear Selection",
                                systemImage: "xmark.circle",
                                action: { appState.router.clearSelection() })
                } else {
                    BatchButton(title: isCompact ? "Fav" : "Favorite",
                                systemImage: "star",
                                action: { appState.router.toggleFavorite(appState.selectedScreenshots) })
                    BatchButton(title: isCompact ? "Tag" : "Add Tag",
                                systemImage: "tag",
                                action: { appState.router.addTag(appState.selectedScreenshots) })
                    BatchButton(title: isCompact ? "Folder" : "Collection",
                                systemImage: "folder",
                                action: { appState.router.moveToCollection(appState.selectedScreenshots) })
                    BatchButton(title: isCompact ? "PDF" : "Merge PDF",
                                systemImage: "doc.on.doc",
                                action: { appState.router.mergeIntoPDF(appState.selectedScreenshots) })
                    BatchButton(title: isCompact ? "Export" : "Export Originals",
                                systemImage: "square.and.arrow.up",
                                action: { appState.router.exportOriginals(appState.selectedScreenshots) })
                    BatchButton(title: "Trash",
                                systemImage: "trash",
                                style: .destructive,
                                action: { appState.router.moveToTrash(appState.selectedScreenshots) })
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.SemanticColor.divider.opacity(0.45), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 48)
        .padding(.horizontal, Theme.Layout.batchBarHorizontalInset)
        .padding(.bottom, Theme.Layout.batchBarBottomInset)
        .onAppear {
            print("[BatchBar] appear; selected count:", appState.selection.count)
        }
        .onChange(of: appState.selection.count) { _, newValue in
            print("[BatchBar] selected count:", newValue)
        }
    }
}

private enum BatchButtonStyle { case standard, destructive }

private struct BatchButton: View {
    let title: String
    let systemImage: String
    var style: BatchButtonStyle = .standard
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .foregroundStyle(foreground)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        switch style {
        case .standard:
            return isHovering
                ? Theme.SemanticColor.label.opacity(0.07)
                : Theme.SemanticColor.quietFill.opacity(0.6)
        case .destructive:
            return isHovering
                ? Color.red.opacity(0.16)
                : Color.red.opacity(0.10)
        }
    }

    private var foreground: Color {
        switch style {
        case .standard:    return Theme.SemanticColor.label.opacity(0.88)
        case .destructive: return Color.red.opacity(0.82)
        }
    }
}
