import SwiftUI

/// Mode-adaptive split layout.
///
/// - regular (≥1100): full three-column NavigationSplitView
///   (Sidebar / Grid / Inspector). Sidebar and inspector stay pinned at their
///   declared widths; only the center grid absorbs slack. We deliberately do
///   NOT use `.balanced` — it distributes extra width across all columns and
///   makes the inspector grow into the grid.
/// - medium (≥800): two-column NavigationSplitView (Sidebar + Grid). The
///   inspector is hidden by default but can be re-opened from the toolbar
///   via `appState.inspectorOverrideVisible`, in which case we still render
///   three columns.
/// - compact (<800): bare grid. Sidebar and inspector are hidden. Toolbar
///   toggles surface them on demand.
///
/// The active mode is decided by a `GeometryReader` here (not in the window
/// view) so the measurement reflects the actual content area, not the window
/// frame minus chrome.
struct MainSplitView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { proxy in
            content
                .onAppear { updateMode(width: proxy.size.width) }
                .onChange(of: proxy.size.width) { _, newWidth in
                    updateMode(width: newWidth)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.layoutMode {
        case .regular:
            threeColumn
        case .medium:
            if appState.inspectorOverrideVisible {
                threeColumn
            } else {
                twoColumn
            }
        case .compact:
            if appState.sidebarOverrideVisible && appState.inspectorOverrideVisible {
                threeColumn
            } else if appState.sidebarOverrideVisible {
                twoColumn
            } else if appState.inspectorOverrideVisible {
                gridPlusInspector
            } else {
                ScreenshotGridContainer()
            }
        }
    }

    private var threeColumn: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ScreenshotGridContainer()
        } detail: {
            InspectorView()
        }
    }

    private var twoColumn: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ScreenshotGridContainer()
        }
    }

    private var gridPlusInspector: some View {
        NavigationSplitView {
            ScreenshotGridContainer()
        } detail: {
            InspectorView()
        }
    }

    private func updateMode(width: CGFloat) {
        let next = Theme.LayoutMode.from(width: width)
        if appState.layoutMode != next {
            print("[MainSplitView] layoutMode \(appState.layoutMode) → \(next) at width=\(Int(width))")
            appState.layoutMode = next
        }
    }
}
