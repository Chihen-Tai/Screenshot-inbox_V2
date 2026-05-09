import SwiftUI

enum ToolbarViewOptionsMenuItem: CaseIterable, Hashable {
    case thumbnailSize
    case sortBy
    case sortDirection
    case toggleSidebar
    case toggleInspector
    case customizeFilters
}

enum ToolbarMoreMenuItem: CaseIterable, Hashable {
    case refreshOCR
    case rerunOCR
    case rerunCodeDetection
    case share
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
    @Binding var thumbnailSize: GridThumbnailSize
    @Binding var sortField: ScreenshotSortField
    @Binding var sortDirection: SortDirection
    let selectedCount: Int
    let isMaintenanceRunning: Bool
    var onImport: () -> Void = {}
    var onRefreshOCR: () -> Void = {}
    var onRerunOCR: () -> Void = {}
    var onRerunCodeDetection: () -> Void = {}
    var onExportPDF: () -> Void = {}
    var onShare: () -> Void = {}
    var onRevealLibraryFolder: () -> Void = {}
    var onRunRulesNow: () -> Void = {}
    var onRebuildThumbnails: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onCustomizeFilters: () -> Void = {}

    var body: some ToolbarContent {
        // Sidebar toggle — borderless icon-only, matches Finder's sidebar toggle style.
        ToolbarItemGroup(placement: .navigation) {
            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .regular))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            .help(mode == .compact
                  ? "Sidebar is hidden in compact windows"
                  : (sidebarVisible ? "Hide sidebar" : "Show sidebar"))
        }

        // Title/subtitle are rendered via .navigationTitle / .navigationSubtitle
        // in MainWindowView — no .principal override so macOS draws them natively.

        ToolbarItemGroup(placement: .primaryAction) {
            // Compact search field: stable width, rectangular (not capsule), right-aligned.
            ToolbarSearchField(query: $searchQuery)

            Divider()
                .padding(.vertical, 5)

            Button {
                onImport()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import screenshots")

            Button {
                onShare()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(selectedCount == 0)
            .help("Share selected screenshots")

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
        case .thumbnailSize:
            Picker("Thumbnail Size", selection: $thumbnailSize) {
                ForEach(GridThumbnailSize.allCases, id: \.self) { size in
                    Text(size.title).tag(size)
                }
            }
        case .sortBy:
            Picker("Sort By", selection: $sortField) {
                ForEach(ScreenshotSortField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
        case .sortDirection:
            Picker("Sort Direction", selection: $sortDirection) {
                ForEach(SortDirection.allCases, id: \.self) { direction in
                    Text(direction.title).tag(direction)
                }
            }
        case .toggleSidebar:
            Toggle("Left Sidebar", isOn: $sidebarVisible)
        case .toggleInspector:
            Toggle("Right Inspector", isOn: $inspectorVisible)
        case .customizeFilters:
            Button("Customize Filters…", systemImage: "line.3.horizontal.decrease.circle") {
                onCustomizeFilters()
            }
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
        case .share:
            Button("Share…", systemImage: "square.and.arrow.up") {
                onShare()
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

/// Compact search field for the toolbar trailing area.
/// Uses a stable fixed width and a rectangular (non-capsule) container
/// so it feels native and doesn't push toolbar height beyond the macOS standard.
private struct ToolbarSearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Search screenshots, OCR, tags…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .accessibilityLabel("Search screenshots")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? Color.accentColor.opacity(0.6)
                        : Color(nsColor: .separatorColor).opacity(0.7),
                    lineWidth: isFocused ? 1 : 0.5
                )
        )
        .animation(.easeInOut(duration: 0.15), value: query.isEmpty)
        .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}
