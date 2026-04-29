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
        guard let url = managedOriginalURL(for: shots.first) else { return }
        do {
            try appState.fileActionService.open(url)
            appState.showToast("Opened \(url.lastPathComponent)", kind: .success)
        } catch {
            appState.showToast(fileActionMessage(for: error), kind: .info)
        }
    }

    func quickLook(_ shots: [Screenshot]) {
        log("quickLook", shots)
        guard let first = shots.first else { return }
        appState.beginPreview(of: first)
    }

    func revealInFinder(_ shots: [Screenshot]) {
        log("revealInFinder", shots)
        guard let url = managedOriginalURL(for: shots.first) else { return }
        do {
            try appState.fileActionService.revealInFinder(url)
            appState.showToast("Revealed in Finder", kind: .success)
        } catch {
            appState.showToast(fileActionMessage(for: error), kind: .info)
        }
    }

    func rename(_ shot: Screenshot) {
        log("rename", [shot])
        appState.beginRename(shot)
    }

    func addTag(_ shots: [Screenshot]) {
        log("addTag", shots)
        appState.beginAddTag(to: shots)
    }

    func moveToCollection(_ shots: [Screenshot]) {
        log("moveToCollection", shots)
        appState.beginAddToCollection(shots)
    }

    func toggleFavorite(_ shots: [Screenshot]) {
        log("toggleFavorite", shots)
        guard !shots.isEmpty else { return }
        let shouldFavorite = shots.contains { !$0.isFavorite }
        appState.setFavorite(ids: Set(shots.map(\.id)), isFavorite: shouldFavorite)
        if shouldFavorite {
            appState.showToast(shots.count == 1 ? "Added to Favorites" : "Added \(shots.count) screenshots to Favorites",
                               kind: .success)
        } else {
            appState.showToast(shots.count == 1 ? "Removed from Favorites" : "Removed \(shots.count) screenshots from Favorites",
                               kind: .success)
        }
    }

    func copyImage(_ shots: [Screenshot]) {
        log("copyImage", shots)
        appState.showToast("Copy Image is coming in a later phase",
                           kind: .comingSoon)
    }

    func copyOCRText(_ shots: [Screenshot]) {
        log("copyOCRText", shots)
        let complete = shots.filter { $0.isOCRComplete && !$0.ocrSnippets.isEmpty }
        guard !complete.isEmpty else {
            appState.showToast("OCR text is not available yet", kind: .info)
            return
        }
        let blocks = complete.map { shot in
            let text = shot.ocrSnippets.joined(separator: "\n")
            return complete.count == 1 ? text : "\(shot.name)\n\(text)"
        }
        let payload = blocks.joined(separator: "\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(payload, forType: .string)
        let n = complete.count
        let suffix = n == 1 ? "" : "s"
        appState.showToast("Copied OCR text from \(n) screenshot\(suffix)",
                           kind: .success)
    }

    func rerunOCR(_ shots: [Screenshot]) {
        log("rerunOCR", shots)
        appState.rerunOCR(for: shots)
    }

    func openDetectedLink(_ shots: [Screenshot]) {
        log("openDetectedLink", shots)
        guard let shot = shots.first,
              let code = appState.detectedCodes(for: shot).first(where: \.isURL) else {
            appState.showToast("No detected link", kind: .info)
            return
        }
        appState.openDetectedCode(code)
    }

    func copyDetectedLink(_ shots: [Screenshot]) {
        log("copyDetectedLink", shots)
        guard let shot = shots.first,
              let code = appState.detectedCodes(for: shot).first else {
            appState.showToast("No detected code", kind: .info)
            return
        }
        appState.copyDetectedCode(code)
    }

    func rerunCodeDetection(_ shots: [Screenshot]) {
        log("rerunCodeDetection", shots)
        appState.rerunCodeDetection(for: shots)
    }

    func mergeIntoPDF(_ shots: [Screenshot]) {
        log("mergeIntoPDF", shots)
        appState.beginPDFExport(shots)
    }

    func moveToTrash(_ shots: [Screenshot]) {
        log("moveToTrash", shots)
        guard !shots.isEmpty else { return }
        appState.trash(ids: Set(shots.map(\.id)))
        let n = shots.count
        let suffix = n == 1 ? "" : "s"
        appState.showToast("Moved \(n) screenshot\(suffix) to Trash", kind: .success)
    }

    func restoreFromTrash(_ shots: [Screenshot]) {
        log("restoreFromTrash", shots)
        guard !shots.isEmpty else { return }
        appState.untrash(ids: Set(shots.map(\.id)))
        let n = shots.count
        let suffix = n == 1 ? "" : "s"
        appState.showToast("Restored \(n) screenshot\(suffix)", kind: .success)
    }

    func deletePermanentlyPlaceholder(_ shots: [Screenshot]) {
        log("deletePermanentlyPlaceholder", shots)
        appState.showToast("Permanent delete is coming in a later phase", kind: .comingSoon)
    }

    func handleDeleteKey(_ shots: [Screenshot]) {
        if appState.sidebarSelection == .trash {
            deletePermanentlyPlaceholder(shots)
        } else {
            moveToTrash(shots)
        }
    }

    func addDraggedScreenshotsToFavorites(ids: [UUID]) {
        print("[Router] sidebar favorite drop ids=\(ids.map(\.uuidString))")
        let shots = appState.screenshots(for: ids).filter { !$0.isTrashed }
        guard !shots.isEmpty else { return }
        appState.setFavorite(ids: Set(shots.map(\.id)), isFavorite: true)
        let n = shots.count
        appState.showToast("Added \(n) screenshot\(n == 1 ? "" : "s") to Favorites",
                           kind: .success)
    }

    func moveDraggedScreenshotsToTrash(ids: [UUID]) {
        print("[Router] sidebar trash drop ids=\(ids.map(\.uuidString))")
        let shots = appState.screenshots(for: ids).filter { !$0.isTrashed }
        guard !shots.isEmpty else { return }
        moveToTrash(shots)
    }

    func addDraggedScreenshots(ids: [UUID], toCollection collectionUUID: String) {
        print("[Router] sidebar collection drop collection=\(collectionUUID) ids=\(ids.map(\.uuidString))")
        let validIDs = appState.screenshots(for: ids).filter { !$0.isTrashed }.map(\.id)
        guard !validIDs.isEmpty else { return }
        appState.addScreenshots(ids: validIDs, toCollection: collectionUUID)
    }

    // MARK: - Empty-area / global actions

    func importScreenshots() {
        appState.showToast("Import is coming in a later phase", kind: .comingSoon)
    }

    func newCollection() {
        appState.createNewCollection()
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

    private func managedOriginalURL(for shot: Screenshot?) -> URL? {
        guard let shot else { return nil }
        guard let url = appState.thumbnailProvider.originalURL(for: shot) else {
            appState.showToast("File not found", kind: .info)
            return nil
        }
        return url
    }

    private func fileActionMessage(for error: Error) -> String {
        switch error {
        case MacFileActionError.missingFile:
            return "File not found"
        case MacFileActionError.openFailed:
            return "Could not open file"
        default:
            return "File action failed"
        }
    }
}
