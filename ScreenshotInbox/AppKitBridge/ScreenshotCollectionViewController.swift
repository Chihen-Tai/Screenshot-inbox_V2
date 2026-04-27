import AppKit

/// Owns the `NSCollectionView` that renders the screenshot grid.
///
/// Phase 4: multi-selection sync + keyboard. The `SelectionController` is the
/// source of truth; this controller mirrors its `selectedIDs` into the
/// collection view, forwards item clicks (with modifier flags), and routes
/// the standard `selectAll(_:)` / `cancelOperation(_:)` actions (Cmd-A /
/// Escape) up to SwiftUI via callbacks.
///
/// Drag/drop, marquee select, context menu, keyboard arrows live in dedicated
/// controllers (Phase 5+).
final class ScreenshotCollectionViewController: NSViewController {
    private(set) var screenshots: [Screenshot] = []
    private(set) var screenshotIDs: [UUID] = []
    private var currentSelectedIDs: Set<UUID> = []
    private var isApplyingExternalSelection = false

    /// Click callback. The container resolves modifier flags to the right
    /// SelectionController call (replace / toggle / extendRange).
    var onItemClick: ((UUID, NSEvent.ModifierFlags) -> Void)?
    /// Background click (empty grid area) clears selection.
    var onBackgroundClick: (() -> Void)?
    /// Cmd-A — fired by AppKit's standard `selectAll(_:)` action and the
    /// `performKeyEquivalent` fallback on the collection view subclass.
    var onSelectAll: (() -> Void)?
    /// Escape — fired by AppKit's `cancelOperation(_:)`.
    var onClear: (() -> Void)?

    private let layout = ScreenshotCollectionViewLayout()
    private var currentLayoutMode: Theme.LayoutMode = .regular
    private var currentParams: Theme.Layout.Grid.ModeParams =
        Theme.Layout.Grid.params(for: .regular)
    private(set) var collectionView: NSCollectionView!
    private(set) var scrollView: NSScrollView!

    /// Push the SwiftUI-side layout mode into the AppKit flow layout. Skipped
    /// when the mode hasn't changed so we don't churn `invalidateLayout()`.
    /// Visible cells are also rebuilt to the new params (font, checkmark,
    /// thumb aspect) so the mode flip is visually consistent immediately.
    func applyLayoutMode(_ mode: Theme.LayoutMode) {
        guard mode != currentLayoutMode else { return }
        currentLayoutMode = mode
        let params = Theme.Layout.Grid.params(for: mode)
        currentParams = params
        layout.apply(params: params)
        if let cv = collectionView {
            for case let cell as ScreenshotCollectionViewItem in cv.visibleItems() {
                cell.applyParams(params)
            }
        }
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay

        let cv = ScreenshotGridCollectionView()
        cv.collectionViewLayout = layout
        cv.delegate = self
        cv.dataSource = self
        cv.isSelectable = true
        cv.allowsEmptySelection = true
        cv.allowsMultipleSelection = true
        cv.backgroundColors = [.clear]
        cv.onBackgroundClick = { [weak self] in self?.onBackgroundClick?() }
        cv.onSelectAllShortcut = { [weak self] in self?.onSelectAll?() }
        cv.onClearShortcut = { [weak self] in self?.onClear?() }
        cv.register(
            ScreenshotCollectionViewItem.self,
            forItemWithIdentifier: ScreenshotCollectionViewItem.identifier
        )

        scroll.documentView = cv

        self.collectionView = cv
        self.scrollView = scroll
        self.view = scroll
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Belt-and-braces: ensure the grid owns the keyboard so Cmd-A and
        // Escape land here. `viewDidMoveToWindow` on the collection view
        // already does this, but a representable can re-host the controller.
        view.window?.makeFirstResponder(collectionView)
        print("[Grid] viewDidAppear; firstResponder=\(String(describing: view.window?.firstResponder))")
        // Note: the window-level NSEvent monitor is now installed by
        // AppState.installShortcuts() from MainWindowView.onAppear, so it
        // runs once per window regardless of whether viewDidAppear fires.
    }

    /// Recompute the flow layout whenever the host view (and therefore the
    /// scroll-view + collection-view bounds) changes width. The layout's
    /// `prepare()` re-derives column count and item size from the current
    /// available width, so calling `invalidateLayout()` here keeps the grid
    /// fluid as the user resizes the window.
    private var lastLaidOutWidth: CGFloat = 0
    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        if abs(w - lastLaidOutWidth) > 0.5 {
            lastLaidOutWidth = w
            collectionView?.collectionViewLayout?.invalidateLayout()
        }
    }

    /// Diffs incoming SwiftUI state and applies to the AppKit collection view.
    /// Avoids `reloadData()` when the dataset is unchanged.
    func applyDataIfNeeded(screenshots: [Screenshot], selectedIDs: Set<UUID>) {
        let newIDs = screenshots.map(\.id)
        let needsReload = newIDs != screenshotIDs
        if needsReload {
            self.screenshots = screenshots
            self.screenshotIDs = newIDs
            collectionView?.reloadData()
        }
        if needsReload || selectedIDs != currentSelectedIDs {
            currentSelectedIDs = selectedIDs
            applyExternalSelection(selectedIDs)
        }
    }

    private func applyExternalSelection(_ ids: Set<UUID>) {
        guard let cv = collectionView else { return }
        isApplyingExternalSelection = true
        defer { isApplyingExternalSelection = false }
        cv.deselectAll(nil)
        guard !ids.isEmpty else { return }
        var paths: Set<IndexPath> = []
        for (i, id) in screenshotIDs.enumerated() where ids.contains(id) {
            paths.insert(IndexPath(item: i, section: 0))
        }
        cv.selectItems(at: paths, scrollPosition: [])
    }

    fileprivate func dispatchClick(at indexPath: IndexPath, modifiers: NSEvent.ModifierFlags) {
        guard indexPath.item < screenshots.count else { return }
        // Item subviews swallow mouseDown, so the collection view never sees
        // the click — manually take focus so the next Cmd-A / Escape lands here.
        collectionView.window?.makeFirstResponder(collectionView)
        let id = screenshots[indexPath.item].id
        onItemClick?(id, modifiers)
    }
}

// MARK: - DataSource

extension ScreenshotCollectionViewController: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        screenshots.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let raw = collectionView.makeItem(
            withIdentifier: ScreenshotCollectionViewItem.identifier,
            for: indexPath
        )
        guard let item = raw as? ScreenshotCollectionViewItem else { return raw }
        item.applyParams(currentParams)
        if indexPath.item < screenshots.count {
            item.configure(with: screenshots[indexPath.item])
        }
        // Wire the item's click handler. Click semantics are owned by the
        // SelectionController via the controller's onItemClick callback.
        item.onClick = { [weak self, weak item] mods in
            guard let self, let item,
                  let path = self.collectionView.indexPath(for: item) else { return }
            self.dispatchClick(at: path, modifiers: mods)
        }
        return item
    }
}

// MARK: - Delegate

extension ScreenshotCollectionViewController: NSCollectionViewDelegate {
    // Item-level mouseDown drives selection now. The default delegate paths
    // would lose modifier flags, so we keep them as no-ops.
    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        _ = isApplyingExternalSelection
    }

    func collectionView(_ collectionView: NSCollectionView,
                        didDeselectItemsAt indexPaths: Set<IndexPath>) {
        // No-op for the same reason as above.
    }
}

// MARK: - Grid collection view (focus + keyboard + background click)

/// NSCollectionView subclass that:
/// 1. Becomes first responder on mount and on click so Cmd-A / Escape are
///    delivered here instead of being eaten by the menu or sibling views.
/// 2. Routes AppKit's standard `selectAll(_:)` (Cmd-A) and `cancelOperation(_:)`
///    (Escape) actions to SwiftUI via callbacks. Overriding the actions —
///    rather than relying on a window-level `keyDown` monitor — works whether
///    the shortcut is delivered as a key event, a menu key equivalent, or via
///    accessibility, and it cooperates with `NSTextField`'s default Cmd-A
///    (text select-all) when the search field is focused, since the action
///    only fires on the responder chain.
/// 3. Forwards empty-area clicks so the container can clear selection.
final class ScreenshotGridCollectionView: NSCollectionView {
    var onBackgroundClick: (() -> Void)?
    var onSelectAllShortcut: (() -> Void)?
    var onClearShortcut: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        print("[Grid] viewDidMoveToWindow; window=\(window != nil); firstResponder=\(String(describing: window?.firstResponder))")
    }

    override func mouseDown(with event: NSEvent) {
        // Reclaim focus on every click — sidebar / inspector may have stolen it.
        window?.makeFirstResponder(self)
        let local = convert(event.locationInWindow, from: nil)
        if indexPathForItem(at: local) == nil {
            onBackgroundClick?()
        }
        super.mouseDown(with: event)
    }

    /// Standard Cmd-A path. Edit > Select All sends this action up the
    /// responder chain; we route it to the SelectionController instead of
    /// NSCollectionView's built-in selection so SwiftUI stays the source of truth.
    override func selectAll(_ sender: Any?) {
        print("[Grid] selectAll(_:) fired")
        onSelectAllShortcut?()
    }

    /// Standard Escape path.
    override func cancelOperation(_ sender: Any?) {
        print("[Grid] cancelOperation(_:) fired")
        onClearShortcut?()
    }

    /// Belt-and-braces Cmd-A handler. If a SwiftUI command or menu item
    /// claims Cmd-A as a key equivalent, `performKeyEquivalent` runs first
    /// across the view hierarchy — winning here keeps the shortcut working
    /// even if the responder-chain action route is short-circuited. We allow
    /// CapsLock / fn / numericPad noise on the flags, which the previous
    /// strict `mods == .command` check rejected.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandOnly = mods.contains(.command)
            && !mods.contains(.shift)
            && !mods.contains(.option)
            && !mods.contains(.control)
        if isCommandOnly,
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            print("[Grid] performKeyEquivalent caught Cmd-A")
            onSelectAllShortcut?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
