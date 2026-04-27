import AppKit
import Foundation

/// Phase 5: single dispatch point for every screenshot action.
///
/// Context menu items, the batch action bar, the inspector action rows, and
/// keyboard shortcuts all call into this router so the same intent ("trash
/// the selection", "merge into PDF", etc.) is implemented exactly once. Most
/// destinations are placeholders for now and surface a toast via `AppState`.
///
/// The router doesn't itself emit `objectWillChange` — observable state lives
/// on `AppState` (toast banner, preview/rename overlays, mock trash). That
/// keeps the SwiftUI subscription graph simple: views observe AppState and
/// see every action's effect, no second `@EnvironmentObject` to thread.
@MainActor
final class ScreenshotActionRouter {
    /// Avoid retain cycles — `AppState` owns the router, the router only
    /// reaches back to mutate published state.
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Targeting helper

    /// Right-click selection sync rule:
    /// - Click hits a screenshot already in the selection → keep the whole
    ///   multi-selection.
    /// - Click hits an unselected screenshot → replace selection with that
    ///   single item before showing the menu.
    /// - Click hits empty space (`nil`) → leave selection alone.
    /// Mirrors Finder. Returns the targets the menu should operate on.
    @discardableResult
    func syncSelectionForContextMenu(rightClickedID: UUID?) -> [Screenshot] {
        if let id = rightClickedID, !appState.selectedScreenshotIDs.contains(id) {
            appState.selection.replace(with: id)
        }
        return appState.selectedScreenshots
    }

    // MARK: - Item-level actions

    func open(_ shots: [Screenshot]) {
        log("open", shots)
        appState.showToast("Open is coming in a later phase", kind: .comingSoon)
    }

    func quickLook(_ shots: [Screenshot]) {
        log("quickLook", shots)
        guard let first = shots.first else { return }
        appState.beginPreview(of: first)
    }

    func revealInFinder(_ shots: [Screenshot]) {
        log("revealInFinder", shots)
        appState.showToast("Reveal in Finder isn't connected to real files yet",
                           kind: .comingSoon)
    }

    func rename(_ shot: Screenshot) {
        log("rename", [shot])
        appState.beginRename(shot)
    }

    func addTag(_ shots: [Screenshot]) {
        log("addTag", shots)
        appState.showToast("Add Tag is coming in a later phase", kind: .comingSoon)
    }

    func moveToCollection(_ shots: [Screenshot]) {
        log("moveToCollection", shots)
        appState.showToast("Move to Collection is coming in a later phase",
                           kind: .comingSoon)
    }

    func copyImage(_ shots: [Screenshot]) {
        log("copyImage", shots)
        appState.showToast("Copy Image is coming in a later phase",
                           kind: .comingSoon)
    }

    /// Mock-OCR copy: dumps each selected screenshot's mock `ocrSnippets` onto
    /// the system pasteboard so the action gives real, observable feedback even
    /// though no real OCR is wired yet.
    func copyOCRText(_ shots: [Screenshot]) {
        log("copyOCRText", shots)
        let blocks = shots.map { shot in
            shot.ocrSnippets.joined(separator: "\n")
        }
        let payload = blocks.joined(separator: "\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(payload, forType: .string)
        let n = shots.count
        let suffix = n == 1 ? "" : "s"
        appState.showToast("Copied OCR text from \(n) screenshot\(suffix)",
                           kind: .success)
    }

    func mergeIntoPDF(_ shots: [Screenshot]) {
        log("mergeIntoPDF", shots)
        let n = shots.count
        let suffix = n == 1 ? "" : "s"
        appState.showToast("Merge \(n) screenshot\(suffix) into PDF is coming in a later phase",
                           kind: .comingSoon)
    }

    func moveToTrash(_ shots: [Screenshot]) {
        log("moveToTrash", shots)
        guard !shots.isEmpty else { return }
        appState.trash(ids: Set(shots.map(\.id)))
        let n = shots.count
        let suffix = n == 1 ? "" : "s"
        appState.showToast("\(n) screenshot\(suffix) moved to Trash", kind: .success)
    }

    // MARK: - Empty-area / global actions

    func importScreenshots() {
        appState.showToast("Import is coming in a later phase", kind: .comingSoon)
    }

    func newCollection() {
        appState.showToast("New Collection is coming in a later phase",
                           kind: .comingSoon)
    }

    func selectAll() {
        appState.selectAllVisibleScreenshots()
    }

    func clearSelection() {
        appState.clearScreenshotSelection()
    }

    // MARK: - Diagnostics

    private func log(_ action: String, _ shots: [Screenshot]) {
        let names = shots.prefix(3).map(\.name).joined(separator: ", ")
        let extra = shots.count > 3 ? " (+\(shots.count - 3) more)" : ""
        print("[Router] \(action) — \(shots.count) target(s): \(names)\(extra)")
    }
}
