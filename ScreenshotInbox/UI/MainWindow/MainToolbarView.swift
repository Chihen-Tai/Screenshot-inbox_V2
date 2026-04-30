import SwiftUI

enum ToolbarViewOptionsMenuItem: CaseIterable, Hashable {
    case toggleSidebar
    case toggleInspector
}

enum ToolbarMoreMenuItem: CaseIterable, Hashable {
    case refreshOCR
    case rerunOCR
    case rerunCodeDetection
    case exportPDF
    case revealLibraryFolder
    case runRulesNow
    case rebuildThumbnails
    case openSettings
}

/// Native macOS toolbar content for the main window.
/// The window title is set via `.navigationTitle(...)` on the parent view —
/// this toolbar intentionally does NOT render its own title, to avoid the
/// "OCR Pending    ScreenshotInbox" duplication.
struct MainToolbarView: ToolbarContent {
    @Binding var searchQuery: String
    let mode: Theme.LayoutMode
    @Binding var sidebarVisible: Bool
    @Binding var inspectorVisible: Bool
    let selectedCount: Int
    let isMaintenanceRunning: Bool
    var onImport: () -> Void = {}
    var onRefreshOCR: () -> Void = {}
    var onRerunOCR: () -> Void = {}
    var onRerunCodeDetection: () -> Void = {}
    var onExportPDF: () -> Void = {}
    var onRevealLibraryFolder: () -> Void = {}
    var onRunRulesNow: () -> Void = {}
    var onRebuildThumbnails: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                sidebarVisible.toggle()
            } label: {
                Label("Sidebar", systemImage: "sidebar.left")
            }
            .help(mode == .compact
                  ? "Sidebar is hidden in compact windows"
                  : (sidebarVisible ? "Hide sidebar" : "Show sidebar"))
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                TextField("Search filename, OCR, tags, QR links...", text: $searchQuery)
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

            Menu {
                ForEach(ToolbarViewOptionsMenuItem.allCases, id: \.self) { item in
                    viewOptionsMenuItem(item)
                }
            } label: {
                Label("View Options", systemImage: "slider.horizontal.3")
            }
            .help("View options")

            Button {
                inspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: inspectorVisible ? "sidebar.trailing" : "sidebar.right")
            }
            .help(inspectorVisible ? "Hide inspector" : "Show inspector")

            Menu {
                ForEach(ToolbarMoreMenuItem.allCases, id: \.self) { item in
                    moreMenuItem(item)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More")
        }
    }

    @ViewBuilder
    private func viewOptionsMenuItem(_ item: ToolbarViewOptionsMenuItem) -> some View {
        switch item {
        case .toggleSidebar:
            Toggle("Left Sidebar", isOn: $sidebarVisible)
        case .toggleInspector:
            Toggle("Right Inspector", isOn: $inspectorVisible)
        }
    }

    @ViewBuilder
    private func moreMenuItem(_ item: ToolbarMoreMenuItem) -> some View {
        switch item {
        case .refreshOCR:
            Button("Refresh OCR", systemImage: "arrow.clockwise") {
                onRefreshOCR()
            }
        case .rerunOCR:
            Button("Refresh OCR for Selection", systemImage: "text.viewfinder") {
                onRerunOCR()
            }
            .disabled(selectedCount == 0)
        case .rerunCodeDetection:
            Button("Re-run QR Detection", systemImage: "qrcode.viewfinder") {
                onRerunCodeDetection()
            }
            .disabled(selectedCount == 0)
        case .exportPDF:
            Button("Export as PDF", systemImage: "doc.richtext") {
                onExportPDF()
            }
            .disabled(selectedCount == 0)
        case .revealLibraryFolder:
            Button("Reveal Library Folder", systemImage: "folder") {
                onRevealLibraryFolder()
            }
        case .runRulesNow:
            Button("Run Rules Now", systemImage: "wand.and.stars") {
                onRunRulesNow()
            }
            .disabled(selectedCount == 0)
        case .rebuildThumbnails:
            Button("Rebuild Thumbnails", systemImage: "photo.stack") {
                onRebuildThumbnails()
            }
            .disabled(isMaintenanceRunning)
        case .openSettings:
            Button("Open Settings", systemImage: "gearshape") {
                onOpenSettings()
            }
        }
    }
}
