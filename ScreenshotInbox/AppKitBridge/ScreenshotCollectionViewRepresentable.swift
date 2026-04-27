import SwiftUI
import AppKit

/// SwiftUI bridge to the AppKit-backed screenshot grid.
///
/// Phase 4: passes the full `selectedIDs` set and routes clicks (with
/// modifier flags) back to `onClick(id, modifiers)`. Cmd-A and Escape are
/// delivered through `onSelectAll` / `onClear`, fired by the collection
/// view's responder-chain actions (see `ScreenshotGridCollectionView`).
struct ScreenshotCollectionViewRepresentable: NSViewControllerRepresentable {
    let screenshots: [Screenshot]
    let selectedIDs: Set<UUID>
    let layoutMode: Theme.LayoutMode
    let onClick: (UUID, NSEvent.ModifierFlags) -> Void
    let onBackgroundClick: () -> Void
    let onSelectAll: () -> Void
    let onClear: () -> Void

    func makeNSViewController(context: Context) -> ScreenshotCollectionViewController {
        let vc = ScreenshotCollectionViewController()
        vc.onItemClick = onClick
        vc.onBackgroundClick = onBackgroundClick
        vc.onSelectAll = onSelectAll
        vc.onClear = onClear
        vc.applyLayoutMode(layoutMode)
        vc.applyDataIfNeeded(screenshots: screenshots, selectedIDs: selectedIDs)
        return vc
    }

    func updateNSViewController(_ vc: ScreenshotCollectionViewController, context: Context) {
        vc.onItemClick = onClick
        vc.onBackgroundClick = onBackgroundClick
        vc.onSelectAll = onSelectAll
        vc.onClear = onClear
        vc.applyLayoutMode(layoutMode)
        vc.applyDataIfNeeded(screenshots: screenshots, selectedIDs: selectedIDs)
    }
}
