import Foundation
import Combine
import AppKit

/// Single source of truth for the prototype.
///
/// Owns: sidebar selection, filter chip, search query, layout mode, mock
/// screenshot store (mutable for Phase 5 mock trash + rename), selection
/// (delegated to `SelectionController`), preview / rename overlay state,
/// toast banner, and the central `ScreenshotActionRouter`.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Sidebar / filter / search

    @Published var sidebarSelection: SidebarSelection? = .inbox {
        didSet { pruneSelectionToVisible() }
    }
    @Published var activeFilterChip: FilterChip = .all
    @Published var searchQuery: String = ""

    // MARK: - Window-driven layout overrides

    @Published var layoutMode: Theme.LayoutMode = .regular
    @Published var sidebarOverrideVisible: Bool = false
    @Published var inspectorOverrideVisible: Bool = false

    // MARK: - Phase 5 overlays

    /// Mock Quick Look preview is shown when this is non-nil.
    @Published var previewedScreenshotID: UUID?
    /// Mock rename sheet is shown when this is non-nil.
    @Published var renamingScreenshotID: UUID?
    /// Live rename text-field value. Bound by the rename sheet.
    @Published var pendingRenameText: String = ""
    /// Currently displayed toast / banner. Auto-clears after a short delay.
    @Published var toast: ToastMessage?

    // MARK: - Selection / shortcuts

    let selection: SelectionController
    let shortcuts = WindowShortcutController()

    /// Phase 5 router. Set in `init` after self is fully constructed so it
    /// can hold an `unowned` ref back without ordering trouble.
    private(set) var router: ScreenshotActionRouter!

    // MARK: - Mock screenshot store (mutable for Phase 5)

    /// Canonical newest-first id order. Order is stable across mutations —
    /// only `screenshotsByID` changes when a row is renamed or trashed.
    private var orderedIDs: [UUID]
    private var screenshotsByID: [UUID: Screenshot]

    /// All screenshots in the canonical order, including trashed.
    var allScreenshots: [Screenshot] {
        orderedIDs.compactMap { screenshotsByID[$0] }
    }

    // MARK: - Internals

    private var selectionForwarder: AnyCancellable?
    private var toastDismissTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let mocks = Screenshot.mocks
        self.orderedIDs = mocks.map(\.id)
        self.screenshotsByID = Dictionary(uniqueKeysWithValues: mocks.map { ($0.id, $0) })

        let controller = SelectionController()
        self.selection = controller

        // Forward selection changes so anyone observing AppState updates too.
        self.selectionForwarder = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        self.router = ScreenshotActionRouter(appState: self)

        // Pre-seed one item so the inspector populates on launch.
        if let first = mocks.first {
            controller.replace(with: first.id)
        }
        print("[AppState] init instance:", ObjectIdentifier(self))
    }

    // MARK: - Filtering

    /// Visible-in-grid screenshots after sidebar + filter chip + trash rules.
    /// Trash sidebar shows trashed only; everything else hides trashed.
    var filteredScreenshots: [Screenshot] {
        let isTrashView = sidebarSelection == .trash
        let base = allScreenshots.filter { $0.isTrashed == isTrashView }
        switch activeFilterChip {
        case .all:         return base
        case .favorites:   return base.filter(\.isFavorite)
        case .ocrComplete: return base.filter(\.isOCRComplete)
        case .tagged:      return base.filter { !$0.tags.isEmpty }
        case .png:         return base.filter { $0.format == "PNG" }
        case .thisWeek:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            return base.filter { $0.createdAt > cutoff }
        }
    }

    var displayTitle: String { sidebarSelection?.displayTitle ?? "Inbox" }

    // MARK: - Selection conveniences

    var selectedScreenshotIDs: Set<UUID> { selection.selectedIDs }
    var selectionCount: Int { selection.count }

    /// First visible (in current grid order) selected screenshot.
    var primarySelection: Screenshot? {
        guard !selection.isEmpty else { return nil }
        let visible = filteredScreenshots
        return visible.first(where: { selection.isSelected($0.id) })
    }

    /// All currently selected screenshots in visible order.
    var selectedScreenshots: [Screenshot] {
        let ids = selection.selectedIDs
        return filteredScreenshots.filter { ids.contains($0.id) }
    }

    /// Drop selection entries that aren't in the current filter result.
    /// Call after sidebar / filter / search changes.
    func pruneSelectionToVisible() {
        selection.prune(visible: filteredScreenshots.map(\.id))
    }

    // MARK: - Shortcut targets

    /// Cmd-A from anywhere — single entry point for "select all visible".
    func selectAllVisibleScreenshots() {
        let ids = filteredScreenshots.map(\.id)
        print("[AppState] selectAllVisibleScreenshots; visible=\(ids.count); instance=\(ObjectIdentifier(self))")
        selection.selectAll(in: ids)
    }

    /// Plain Escape from anywhere — single entry point for "clear selection".
    func clearScreenshotSelection() {
        print("[AppState] clearScreenshotSelection; instance=\(ObjectIdentifier(self))")
        selection.clear()
    }

    /// Phase 5: Escape priority is overlay-first, selection-second. Returns
    /// `true` if it consumed the keystroke (overlay was open or selection
    /// was non-empty), `false` if there was nothing to clear.
    @discardableResult
    func handleEscape() -> Bool {
        if closeOverlayIfPresent() { return true }
        if !selection.isEmpty {
            clearScreenshotSelection()
            return true
        }
        return false
    }

    /// Used by Escape paths and by the router before opening a new overlay
    /// (so the new sheet doesn't stack on top of a stale one).
    @discardableResult
    func closeOverlayIfPresent() -> Bool {
        if previewedScreenshotID != nil {
            print("[AppState] closing preview overlay")
            previewedScreenshotID = nil
            return true
        }
        if renamingScreenshotID != nil {
            print("[AppState] closing rename overlay")
            cancelRename()
            return true
        }
        return false
    }

    /// Convenient predicate for the menu / shortcut layers.
    var hasOverlayPresented: Bool {
        previewedScreenshotID != nil || renamingScreenshotID != nil
    }

    /// Debug helper for the on-screen DEBUG bar.
    func printSelectionState() {
        print("[AppState] selection state: count=\(selection.count); ids=\(Array(selection.selectedIDs))")
    }

    /// Install the window-level keyDown monitor. Called from
    /// `MainWindowView.onAppear`.
    func installShortcuts() {
        print("[AppState] installShortcuts; instance=\(ObjectIdentifier(self))")
        shortcuts.onSelectAll = { [weak self] in
            print("[Shortcut→AppState] onSelectAll")
            self?.selectAllVisibleScreenshots()
        }
        shortcuts.onClearSelection = { [weak self] in
            print("[Shortcut→AppState] onClearSelection")
            self?.handleEscape()
        }
        shortcuts.onTrash = { [weak self] in
            guard let self else { return }
            print("[Shortcut→AppState] onTrash")
            let shots = self.selectedScreenshots
            guard !shots.isEmpty else { return }
            self.router.moveToTrash(shots)
        }
        shortcuts.onPreview = { [weak self] in
            guard let self else { return }
            print("[Shortcut→AppState] onPreview")
            // Spec: pressing Space again toggles the preview off.
            if self.previewedScreenshotID != nil {
                self.previewedScreenshotID = nil
                return
            }
            let shots = self.selectedScreenshots
            self.router.quickLook(shots)
        }
        shortcuts.onRename = { [weak self] in
            guard let self else { return }
            print("[Shortcut→AppState] onRename")
            guard let shot = self.primarySelection else { return }
            self.router.rename(shot)
        }
        shortcuts.install { NSApp.keyWindow }
    }

    // MARK: - Phase 5 mutation surface

    /// Mock trash. Marks the given IDs as `isTrashed = true`. Selection is
    /// pruned so counts stay honest.
    func trash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            screenshotsByID[id]?.isTrashed = true
        }
        objectWillChange.send()
        pruneSelectionToVisible()
    }

    func untrash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            screenshotsByID[id]?.isTrashed = false
        }
        objectWillChange.send()
    }

    // MARK: - Preview overlay

    func beginPreview(of shot: Screenshot) {
        if renamingScreenshotID != nil { cancelRename() }
        previewedScreenshotID = shot.id
    }

    /// Resolves the currently previewed screenshot.
    var previewedScreenshot: Screenshot? {
        guard let id = previewedScreenshotID else { return nil }
        return screenshotsByID[id]
    }

    // MARK: - Rename overlay

    func beginRename(_ shot: Screenshot) {
        if previewedScreenshotID != nil { previewedScreenshotID = nil }
        renamingScreenshotID = shot.id
        pendingRenameText = shot.name
    }

    func cancelRename() {
        renamingScreenshotID = nil
        pendingRenameText = ""
    }

    func commitRename() {
        guard let id = renamingScreenshotID else { return }
        let trimmed = pendingRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            screenshotsByID[id]?.name = trimmed
            objectWillChange.send()
            showToast("Renamed", kind: .success)
        }
        cancelRename()
    }

    /// Resolves the currently renaming screenshot.
    var renamingScreenshot: Screenshot? {
        guard let id = renamingScreenshotID else { return nil }
        return screenshotsByID[id]
    }

    // MARK: - Toast banner

    /// Show a transient banner in the bottom-trailing corner of the window.
    /// Replaces any existing toast and auto-dismisses after ~2.4s.
    func showToast(_ text: String, kind: ToastMessage.Kind = .info) {
        toast = ToastMessage(text: text, kind: kind)
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

/// Lightweight banner payload. Kind drives icon + accent in the toast view.
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: Kind

    enum Kind {
        case info
        case success
        case comingSoon
    }
}
