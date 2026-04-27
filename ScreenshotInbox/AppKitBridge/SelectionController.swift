import AppKit
import Combine
import Foundation

/// Owns the live screenshot selection.
///
/// The grid (AppKit) and the inspector / batch bar (SwiftUI) both read and
/// mutate selection through this single object so logic stays in one place.
/// All ops take an "ordered ID list" when they need to reason about the
/// visible order (range select, select-all, prune-on-filter-change).
///
/// Phase 4 scope: replace / toggle / range / select-all / clear.
/// Phase 5+ will grow keyboard arrow navigation, marquee rect, etc. on top
/// of the same anchor model.
@MainActor
final class SelectionController: ObservableObject {
    @Published private(set) var selectedIDs: Set<UUID> = []
    /// Pivot for Shift-click range selection. Set on every non-shift click.
    @Published private(set) var anchorID: UUID?

    // MARK: - Mutations

    /// Single click on `id`. Replaces selection and resets the anchor.
    func replace(with id: UUID) {
        selectedIDs = [id]
        anchorID = id
    }

    /// Programmatic clear (Escape, sidebar/filter reset).
    func clear() {
        print("[Selection] clear")
        selectedIDs.removeAll()
        anchorID = nil
        print("[Selection] selected IDs now:", selectedIDs)
    }

    /// Command-click toggle. Always re-anchors on the clicked item so
    /// subsequent Shift-clicks pivot from the most recent intent — this
    /// matches Finder behavior.
    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        anchorID = id
    }

    /// Shift-click range. Without an anchor, behaves like a normal click.
    /// With an anchor, replaces selection with the inclusive slice between
    /// the anchor's index and `id`'s index in `orderedIDs`.
    ///
    /// TODO Phase 5: Finder-like additive range (Shift+Cmd, contiguous union).
    func extendRange(to id: UUID, in orderedIDs: [UUID]) {
        guard let anchor = anchorID,
              let lo = orderedIDs.firstIndex(of: anchor),
              let hi = orderedIDs.firstIndex(of: id)
        else {
            replace(with: id)
            return
        }
        let range = lo <= hi ? lo...hi : hi...lo
        selectedIDs = Set(orderedIDs[range])
        // Anchor stays put — Shift-click should still pivot from the original.
    }

    /// Cmd-A. Selects every item currently visible in the grid.
    func selectAll(in orderedIDs: [UUID]) {
        print("[Selection] selectAll count:", orderedIDs.count)
        guard !orderedIDs.isEmpty else { return }
        selectedIDs = Set(orderedIDs)
        if anchorID == nil { anchorID = orderedIDs.first }
        print("[Selection] selected IDs now:", selectedIDs)
    }

    /// Drop selection entries that are no longer visible (e.g. after a
    /// sidebar / filter / search change) so the count stays honest.
    func prune(visible orderedIDs: [UUID]) {
        let visibleSet = Set(orderedIDs)
        let pruned = selectedIDs.intersection(visibleSet)
        if pruned != selectedIDs { selectedIDs = pruned }
        if let a = anchorID, !visibleSet.contains(a) {
            anchorID = pruned.first
        }
    }

    // MARK: - Read helpers

    var count: Int { selectedIDs.count }
    var isEmpty: Bool { selectedIDs.isEmpty }

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    /// Selected IDs in the order they appear in `orderedIDs`. Useful for
    /// "primary selection" (first visible) and stable iteration in views.
    func orderedSelection(in orderedIDs: [UUID]) -> [UUID] {
        orderedIDs.filter { selectedIDs.contains($0) }
    }
}
