import SwiftUI

/// Native macOS toolbar content for the main window.
/// The window title is set via `.navigationTitle(...)` on the parent view —
/// this toolbar intentionally does NOT render its own title, to avoid the
/// "OCR Pending    ScreenshotInbox" duplication.
struct MainToolbarView: ToolbarContent {
    @Binding var searchQuery: String
    let mode: Theme.LayoutMode
    @Binding var sidebarVisible: Bool
    @Binding var inspectorVisible: Bool
    var onImport: () -> Void = {}

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if mode == .compact {
                Button {
                    sidebarVisible.toggle()
                } label: {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .help("Show sidebar")
            }
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                TextField("Search screenshots, OCR, or tags", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(
                        minWidth: Theme.Layout.toolbarSearchMinWidth,
                        idealWidth: Theme.Layout.toolbarSearchIdealWidth,
                        maxWidth: Theme.Layout.toolbarSearchMaxWidth
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Theme.SemanticColor.quietFill)
            )
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                onImport()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import screenshots")

            Button {} label: {
                Label("View Options", systemImage: "slider.horizontal.3")
            }
            .help("View options")

            if mode != .regular {
                Button {
                    inspectorVisible.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show inspector")
            }

            Button {} label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More")
        }
    }
}
