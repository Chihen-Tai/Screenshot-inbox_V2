import SwiftUI
import AppKit

/// SwiftUI bridge to the AppKit-backed screenshot grid.
///
/// Phase 4: passes the full `selectedIDs` set and routes clicks (with
/// modifier flags) back to `onClick(id, modifiers)`. Cmd-A and Escape are
/// delivered through `onSelectAll` / `onClear`, fired by the collection
/// view's responder-chain actions (see `ScreenshotGridCollectionView`).
///
/// Phase 5: also routes right-click menu construction. The container is
/// expected to run the Finder-style selection-sync rule (replace selection
/// with the right-clicked item if it's not already in the selection) inside
/// `onItemMenu` before returning the built menu.
struct ScreenshotCollectionViewRepresentable: NSViewControllerRepresentable {
    let screenshots: [Screenshot]
    let selectedIDs: Set<UUID>
    let layoutMode: Theme.LayoutMode
    let onClick: (UUID, NSEvent.ModifierFlags) -> Void
    let onBackgroundClick: () -> Void
    let onSelectAll: () -> Void
    let onClear: () -> Void
    let onItemMenu: (UUID) -> NSMenu?
    let onEmptyAreaMenu: () -> NSMenu?

    func makeNSViewController(context: Context) -> ScreenshotCollectionViewController {
        let vc = ScreenshotCollectionViewController()
        wireCallbacks(vc)
        vc.applyLayoutMode(layoutMode)
        vc.applyDataIfNeeded(screenshots: screenshots, selectedIDs: selectedIDs)
        return vc
    }

    func updateNSViewController(_ vc: ScreenshotCollectionViewController, context: Context) {
        wireCallbacks(vc)
        vc.applyLayoutMode(layoutMode)
        vc.applyDataIfNeeded(screenshots: screenshots, selectedIDs: selectedIDs)
    }

    private func wireCallbacks(_ vc: ScreenshotCollectionViewController) {
        vc.onItemClick = onClick
        vc.onBackgroundClick = onBackgroundClick
        vc.onSelectAll = onSelectAll
        vc.onClear = onClear
        vc.onItemMenu = onItemMenu
        vc.onEmptyAreaMenu = onEmptyAreaMenu
    }
}
