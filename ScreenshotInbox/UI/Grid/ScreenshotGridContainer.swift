import SwiftUI
import AppKit

/// SwiftUI host for the AppKit grid.
///
/// Phase 5 wiring:
/// - Click → SelectionController (replace / toggle / extendRange).
/// - Background click → clear.
/// - Window-scoped keyboard monitor for Cmd-A / Escape / Delete / Space / Enter.
/// - Right-click → builds `NSMenu` via `ContextMenuController`, with
///   Finder-style selection-sync delegated to the router.
/// - Filter-chip / sidebar changes prune selection so counts stay honest.
struct ScreenshotGridContainer: View {
    @EnvironmentObject private var appState: AppState

    /// Lazily constructed once `appState` is available. The router is owned
    /// by `AppState`; the menu controller just needs unowned refs to both.
    @State private var menuController: ContextMenuController?

    var body: some View {
        VStack(spacing: 0) {
            FilterBarView()
            Divider().opacity(0.4)

            ScreenshotCollectionViewRepresentable(
                screenshots: appState.filteredScreenshots,
                selectedIDs: appState.selectedScreenshotIDs,
                layoutMode: appState.layoutMode,
                onClick: handleClick,
                onBackgroundClick: {
                    print("[GridContainer] background click — clear")
                    appState.clearScreenshotSelection()
                },
                onSelectAll: {
                    print("[GridContainer] selectAll received; instance=\(ObjectIdentifier(appState))")
                    appState.selectAllVisibleScreenshots()
                },
                onClear: {
                    print("[GridContainer] clearSelection received; instance=\(ObjectIdentifier(appState))")
                    appState.clearScreenshotSelection()
                },
                onItemMenu: { id in
                    appState.router.syncSelectionForContextMenu(rightClickedID: id)
                    return ensureMenuController().itemMenu()
                },
                onEmptyAreaMenu: {
                    ensureMenuController().emptyAreaMenu()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.4)
            #if DEBUG
            DebugSelectionBar()
            #endif
            footer
        }
        .overlay(alignment: .bottom) {
            if appState.selection.count >= 2 {
                BatchActionBarView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(keyboardShortcutSink)
        .animation(.easeOut(duration: 0.18), value: appState.selection.count)
        .navigationSplitViewColumnWidth(
            min: Theme.Layout.gridContentMin,
            ideal: Theme.Layout.gridContentIdeal
        )
        .onChange(of: appState.activeFilterChip) { appState.pruneSelectionToVisible() }
        .onChange(of: appState.searchQuery) { appState.pruneSelectionToVisible() }
        .onChange(of: appState.sidebarSelection) { appState.pruneSelectionToVisible() }
    }

    private func ensureMenuController() -> ContextMenuController {
        if let existing = menuController { return existing }
        let made = ContextMenuController(appState: appState, router: appState.router)
        menuController = made
        return made
    }

    /// SwiftUI consumes Cmd-A and Escape inside its own focus system before
    /// AppKit ever sees the keyDown — overrides on `NSCollectionView` and a
    /// window-level `NSEvent` monitor both got starved. Binding shortcuts on
    /// hidden SwiftUI buttons is the layer that actually fires. Cmd-A is
    /// handled in `AppCommands` (with text-field forwarding); Escape lives
    /// here so it stays scoped to the grid window.
    private var keyboardShortcutSink: some View {
        Button(action: handleEscape) { EmptyView() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private func handleEscape() {
        print("[GridContainer] handleEscape; firstResponder=\(AppKitFocusHelper.describeFirstResponder())")
        if AppKitFocusHelper.isTextInputFocused() {
            print("[GridContainer] forwarding cancelOperation to text input")
            NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
            return
        }
        // Phase 5: overlay-first, then selection. Single source of truth on AppState.
        appState.handleEscape()
    }

    private func handleClick(_ id: UUID, _ mods: NSEvent.ModifierFlags) {
        let visibleIDs = appState.filteredScreenshots.map(\.id)
        if mods.contains(.shift) {
            appState.selection.extendRange(to: id, in: visibleIDs)
        } else if mods.contains(.command) {
            appState.selection.toggle(id)
        } else {
            appState.selection.replace(with: id)
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var footerText: String {
        let total = appState.filteredScreenshots.count
        let sel = appState.selection.count
        let totalText = total == 1 ? "1 item" : "\(total) items"
        if sel <= 1 { return totalText }
        return "\(totalText) — \(sel) selected"
    }
}
