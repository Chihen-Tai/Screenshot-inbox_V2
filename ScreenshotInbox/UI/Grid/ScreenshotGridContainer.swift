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
        let selectedCount = appState.selectedScreenshotIDs.count
        let isBatchBarVisible = selectedCount > 1
        let _ = Self.logBatchBarEvaluation(count: selectedCount, visible: isBatchBarVisible)
        VStack(spacing: 0) {
            FilterBarView()
            Divider().opacity(0.4)
            if appState.sidebarSelection == .smart(.duplicates) {
                DuplicateCleanupBanner()
                Divider().opacity(0.4)
            }

            ScreenshotCollectionViewRepresentable(
                screenshots: appState.filteredScreenshots,
                selectedIDs: appState.selectedScreenshotIDs,
                layoutMode: appState.layoutMode,
                thumbnailSize: appState.gridThumbnailSize,
                thumbnailProvider: appState.thumbnailProvider,
                onClick: handleClick,
                onSelectionSnapshot: { ids, source in
                    appState.setSelectedScreenshotIDs(ids, source: source)
                },
                onDoubleClick: handleDoubleClick,
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
                },
                onFileDrop: { urls, unsupportedCount in
                    Task {
                        await appState.importDroppedFileURLs(
                            urls,
                            unsupportedCount: unsupportedCount
                        )
                    }
                },
                onDragMissingFiles: { missingCount in
                    appState.showToast(
                        missingCount == 1
                        ? "1 file could not be dragged because it was missing"
                        : "\(missingCount) files could not be dragged because they were missing",
                        kind: .info
                    )
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if appState.filteredScreenshots.isEmpty && !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "No matching screenshots",
                        systemImage: "magnifyingglass",
                        description: Text("Try searching OCR text, tags, QR links, or filenames.")
                    )
                        .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                }
            }

            Divider().opacity(0.4)
            #if DEBUG
            if appState.showDebugControls {
                DebugSelectionBar()
            }
            #endif
            footer
        }
        .overlay(alignment: .bottom) {
            if isBatchBarVisible {
                BatchActionBarView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(keyboardShortcutSink)
        .animation(.easeOut(duration: 0.18), value: selectedCount)
        .navigationSplitViewColumnWidth(
            min: Theme.Layout.gridContentMin,
            ideal: Theme.Layout.gridContentIdeal
        )
        .onChange(of: appState.activeFilterChip) { appState.pruneSelectionToVisible() }
        .onChange(of: appState.searchQuery) { appState.pruneSelectionToVisible() }
        .onChange(of: appState.sidebarSelection) { appState.pruneSelectionToVisible() }
        .onChange(of: selectedCount) { _, newValue in
            print("[BatchBarDebug] selectedIDs count = \(newValue)")
            print("[BatchBarDebug] visible = \(newValue > 1)")
            print("[BatchBarDebug] source = appState.selectedScreenshotIDs")
        }
    }

    private static func logBatchBarEvaluation(count: Int, visible: Bool) {
        print("[BatchBarDebug] selectedIDs count = \(count)")
        print("[BatchBarDebug] visible = \(visible)")
        print("[BatchBarDebug] source = appState.selectedScreenshotIDs")
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
            appState.extendSelection(to: id, in: visibleIDs, source: "shiftClick")
        } else if mods.contains(.command) {
            appState.toggleSelection(id, source: "cmdClick")
        } else {
            appState.replaceSelection(with: id, source: "mouse")
        }
    }

    private func handleDoubleClick(_ id: UUID) {
        appState.replaceSelection(with: id, source: "mouse")
        guard let shot = appState.screenshots(for: [id]).first else { return }
        appState.router.quickLook([shot])
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

private struct DuplicateCleanupBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.on.square")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.label)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                appState.keepSelectedDuplicateAndTrashGroupExtras()
            } label: {
                Label("Keep Selected", systemImage: "checkmark.circle")
            }
            .disabled(appState.primarySelection.flatMap { appState.duplicateGroup(containing: $0.id) } == nil)
            .help("Keep the selected screenshot and move the other screenshots in its duplicate group to Trash")

            Button {
                appState.trashDuplicateExtrasKeepingRecommended()
            } label: {
                Label("Move Extras to Trash", systemImage: "trash")
            }
            .disabled(appState.duplicateGroups.isEmpty)
            .help("Keep the recommended item in each duplicate group and move the extras to App Trash")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.SemanticColor.quietFill.opacity(0.22))
    }

    private var title: String {
        let groupCount = appState.duplicateGroups.count
        let itemCount = appState.duplicatesCount
        guard groupCount > 0 else { return "No duplicates found" }
        return "\(groupCount) duplicate group\(groupCount == 1 ? "" : "s") • \(itemCount) screenshot\(itemCount == 1 ? "" : "s")"
    }

    private var subtitle: String {
        guard !appState.duplicateGroups.isEmpty else {
            return "Use Advanced settings to rebuild the duplicate index after imports."
        }
        return "Favorites are kept first, then higher resolution, then oldest import."
    }
}
