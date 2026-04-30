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
    private var pendingDragIDs: [UUID] = []
    private var isInternalDragActive = false

    /// Click callback. The container resolves modifier flags to the right
    /// SelectionController call (replace / toggle / extendRange).
    var onItemClick: ((UUID, NSEvent.ModifierFlags) -> Void)?
    /// Full AppKit selection snapshot, used for native selection paths such
    /// as rubber-band selection and collection-view delegate changes.
    var onSelectionSnapshot: ((Set<UUID>, String) -> Void)?
    var onItemDoubleClick: ((UUID) -> Void)?
    /// Background click (empty grid area) clears selection.
    var onBackgroundClick: (() -> Void)?
    /// Cmd-A — fired by AppKit's standard `selectAll(_:)` action and the
    /// `performKeyEquivalent` fallback on the collection view subclass.
    var onSelectAll: (() -> Void)?
    /// Escape — fired by AppKit's `cancelOperation(_:)`.
    var onClear: (() -> Void)?
    /// Phase 5 — right-click on a grid item. The container runs the
    /// Finder-style selection-sync rule (replace if not selected) before
    /// returning the menu so the menu's targets are correct.
    var onItemMenu: ((UUID) -> NSMenu?)?
    /// Phase 5 — right-click on grid background (no item under the cursor).
    var onEmptyAreaMenu: (() -> NSMenu?)?
    /// Phase 6.5 — Finder/Desktop files dropped into the grid.
    var onFileDrop: (([URL], Int) -> Void)?
    var onDragMissingFiles: ((Int) -> Void)?
    var thumbnailProvider: MacThumbnailProvider?

    private let layout = ScreenshotCollectionViewLayout()
    private var currentLayoutMode: Theme.LayoutMode = .regular
    private var currentThumbnailSize: GridThumbnailSize = .medium
    private var currentParams: Theme.Layout.Grid.ModeParams =
        Theme.Layout.Grid.params(for: .regular)
    private(set) var collectionView: NSCollectionView!
    private(set) var scrollView: NSScrollView!

    /// Push the SwiftUI-side layout mode into the AppKit flow layout. Skipped
    /// when the mode hasn't changed so we don't churn `invalidateLayout()`.
    /// Visible cells are also rebuilt to the new params (font, checkmark,
    /// thumb aspect) so the mode flip is visually consistent immediately.
    func applyLayoutMode(_ mode: Theme.LayoutMode, thumbnailSize: GridThumbnailSize) {
        guard mode != currentLayoutMode || thumbnailSize != currentThumbnailSize else { return }
        currentLayoutMode = mode
        currentThumbnailSize = thumbnailSize
        let params = Theme.Layout.Grid.params(for: mode, thumbnailSize: thumbnailSize)
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
        cv.onMenuForLocation = { [weak self] localPoint in
            guard let self else { return nil }
            if let path = cv.indexPathForItem(at: localPoint),
               path.item < self.screenshots.count {
                let id = self.screenshots[path.item].id
                return self.onItemMenu?(id)
            }
            return self.onEmptyAreaMenu?()
        }
        cv.onFileDrop = { [weak self] urls, unsupportedCount in
            self?.onFileDrop?(urls, unsupportedCount)
        }
        cv.onInternalDragEnded = { [weak self] in
            self?.endInternalDrag()
        }
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
            #if DEBUG
            print("[GridLayout] host bounds width=\(Int(w))")
            #endif
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
        } else {
            let changedPaths = screenshots.indices.compactMap { index -> IndexPath? in
                guard index < self.screenshots.count, screenshots[index] != self.screenshots[index] else {
                    return nil
                }
                return IndexPath(item: index, section: 0)
            }
            if !changedPaths.isEmpty {
                self.screenshots = screenshots
                collectionView?.reloadItems(at: Set(changedPaths))
                #if DEBUG
                print("[Rename] collection item reloaded: \(changedPaths.map(\.item))")
                #endif
            }
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

    private func syncSelectionFromCollectionView(reason: String) {
        guard let cv = collectionView else { return }
        print("[SelectionDebug] NSCollectionView selectedIndexPaths count = \(cv.selectionIndexPaths.count)")
        let ids = Set(cv.selectionIndexPaths.compactMap { indexPath -> UUID? in
            guard indexPath.item < screenshots.count else { return nil }
            return screenshots[indexPath.item].id
        })
        print("[SelectionDebug] Mouse/AppKit selected IDs count = \(ids.count)")
        print("[SelectionDebug] syncing to SelectionController count = \(ids.count)")
        currentSelectedIDs = ids
        DispatchQueue.main.async { [weak self] in
            self?.onSelectionSnapshot?(ids, reason)
        }
    }

    fileprivate func dispatchClick(at indexPath: IndexPath, modifiers: NSEvent.ModifierFlags) {
        guard indexPath.item < screenshots.count else { return }
        // Item subviews swallow mouseDown, so the collection view never sees
        // the click — manually take focus so the next Cmd-A / Escape lands here.
        collectionView.window?.makeFirstResponder(collectionView)
        let id = screenshots[indexPath.item].id
        let oldSelection = currentSelectedIDs
        let sourceWasSelected = oldSelection.contains(id)
        pendingDragIDs = sourceWasSelected
            ? screenshotIDs.filter { oldSelection.contains($0) }
            : [id]
        print("[InternalDrag] mouse down item index=\(indexPath.item) uuid=\(id.uuidString) selected=\(sourceWasSelected)")

        let normalizedMods = modifiers.intersection(.deviceIndependentFlagsMask)
        let isPlainClick = normalizedMods.isEmpty || normalizedMods == .function
        if sourceWasSelected && isPlainClick {
            // Finder-style drag: pressing a selected item should not collapse
            // the existing multi-selection before the drag threshold is met.
            return
        }
        onItemClick?(id, modifiers)
    }

    fileprivate func dispatchDoubleClick(at indexPath: IndexPath) {
        guard indexPath.item < screenshots.count else { return }
        let screenshot = screenshots[indexPath.item]
        #if DEBUG
        print("[DoubleClick] item index=\(indexPath.item)")
        print("[DoubleClick] screenshot uuid=\(screenshot.uuidString)")
        if let libraryPath = screenshot.libraryPath {
            print("[DoubleClick] opening path=\(libraryPath)")
        }
        #endif
        onItemDoubleClick?(screenshot.id)
    }

    fileprivate func beginInternalDrag(from item: ScreenshotCollectionViewItem, event: NSEvent) {
        guard !isInternalDragActive else { return }
        guard let indexPath = collectionView.indexPath(for: item),
              indexPath.item < screenshots.count else { return }
        let clickedID = screenshots[indexPath.item].id
        let initialSelection = currentSelectedIDs
        let sourceWasSelected = initialSelection.contains(clickedID)
        let ids = sourceWasSelected
            ? screenshotIDs.filter { initialSelection.contains($0) }
            : [clickedID]
        guard !ids.isEmpty else { return }
        if !sourceWasSelected {
            currentSelectedIDs = [clickedID]
            applyExternalSelection([clickedID])
            onItemClick?(clickedID, [])
        }
        #if DEBUG
        print("[Drag] start index: \(indexPath.item)")
        print("[Drag] initial selection count: \(initialSelection.count)")
        print("[Drag] normalized selection count: \(ids.count)")
        print("[Drag] single item drag: \(ids.count == 1)")
        #endif
        #if DEBUG
        print("[DragSource] started item index=\(indexPath.item) uuid=\(clickedID.uuidString)")
        print("[DragSource] dragged IDs: \(ids.map(\.uuidString))")
        print("[DragSource] writing pasteboard type: \(InternalScreenshotDrag.pasteboardTypeString)")
        #endif

        let itemFrameInCollection = item.view.convert(item.view.bounds, to: collectionView)
            .integral
        #if DEBUG
        print("[Drag] preview frame: x=\(Int(itemFrameInCollection.origin.x)) y=\(Int(itemFrameInCollection.origin.y)) w=\(Int(itemFrameInCollection.width)) h=\(Int(itemFrameInCollection.height))")
        #endif
        let fileURLs = managedFileURLs(for: ids)
        let primaryURL = managedFileURL(for: clickedID) ?? fileURLs.urls.first
        let pasteboardItem = dragPasteboardItem(ids: ids, fileURL: primaryURL)
        #if DEBUG
        print("[DragSource] primary pasteboard types after writing: \(pasteboardItem.types.map(\.rawValue))")
        print("[DragSource] external file URL count: \(fileURLs.urls.count)")
        print("[DragSource] internal ID count: \(ids.count)")
        #endif

        let internalDraggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        internalDraggingItem.setDraggingFrame(
            itemFrameInCollection,
            contents: dragImage(for: item, count: ids.count)
        )
        var draggingItems = [internalDraggingItem]
        for url in fileURLs.urls where url != primaryURL {
            let fileItem = NSDraggingItem(pasteboardWriter: dragPasteboardItem(ids: ids, fileURL: url))
            fileItem.setDraggingFrame(NSRect(origin: itemFrameInCollection.origin, size: .zero), contents: nil)
            draggingItems.append(fileItem)
        }
        if fileURLs.missingCount > 0 {
            #if DEBUG
            print("[DragSource] missing managed files for external drag: \(fileURLs.missingCount)")
            #endif
            onDragMissingFiles?(fileURLs.missingCount)
        }
        #if DEBUG
        print("[DragSource] file URLs: \(fileURLs.urls.map(\.path))")
        #endif
        isInternalDragActive = true
        collectionView.beginDraggingSession(with: draggingItems, event: event, source: collectionView)
    }

    fileprivate func endInternalDrag() {
        isInternalDragActive = false
        pendingDragIDs.removeAll()
    }

    private func dragImage(for item: ScreenshotCollectionViewItem, count: Int) -> NSImage {
        let bounds = item.view.bounds
        let rep = item.view.bitmapImageRepForCachingDisplay(in: bounds)
        let image = NSImage(size: bounds.size)
        if let rep {
            item.view.cacheDisplay(in: bounds, to: rep)
            image.addRepresentation(rep)
        }
        guard count > 1 else { return image }

        image.lockFocus()
        let badgeSize = NSSize(width: 28, height: 22)
        let badgeRect = NSRect(
            x: max(0, bounds.width - badgeSize.width - 8),
            y: max(0, bounds.height - badgeSize.height - 8),
            width: badgeSize.width,
            height: badgeSize.height
        )
        NSColor.controlAccentColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 11, yRadius: 11).fill()
        let text = "\(count)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            ),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }

    private func managedFileURLs(for ids: [UUID]) -> (urls: [URL], missingCount: Int) {
        var urls: [URL] = []
        var missing = 0
        let fileManager = FileManager.default
        for id in ids {
            guard let screenshot = screenshots.first(where: { $0.id == id }),
                  let url = thumbnailProvider?.originalURL(for: screenshot) else {
                missing += 1
                continue
            }
            let exists = fileManager.fileExists(atPath: url.path)
            #if DEBUG
            print("[DragSource] libraryPath exists: \(exists) path=\(url.path)")
            #endif
            guard exists else {
                missing += 1
                continue
            }
            urls.append(url)
        }
        return (urls, missing)
    }

    private func managedFileURL(for id: UUID) -> URL? {
        guard let screenshot = screenshots.first(where: { $0.id == id }),
              let url = thumbnailProvider?.originalURL(for: screenshot),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func dragPasteboardItem(ids: [UUID], fileURL: URL?) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(
            InternalScreenshotDrag.encode(ids),
            forType: InternalScreenshotDrag.pasteboardType
        )
        if let fileURL {
            item.setString(fileURL.absoluteString, forType: .fileURL)
            item.setString(fileURL.path, forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        }
        return item
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
            item.configure(with: screenshots[indexPath.item], thumbnailProvider: thumbnailProvider)
        }
        // Wire the item's click handler. Click semantics are owned by the
        // SelectionController via the controller's onItemClick callback.
        item.onClick = { [weak self, weak item] mods in
            guard let self, let item,
                  let path = self.collectionView.indexPath(for: item) else { return }
            self.dispatchClick(at: path, modifiers: mods)
        }
        item.onDoubleClick = { [weak self, weak item] in
            guard let self, let item,
                  let path = self.collectionView.indexPath(for: item) else { return }
            self.dispatchDoubleClick(at: path)
        }
        item.onDrag = { [weak self, weak item] event in
            guard let self, let item else { return }
            self.beginInternalDrag(from: item, event: event)
        }
        return item
    }
}

// MARK: - Delegate

extension ScreenshotCollectionViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        print("[SelectionDebug] NSCollectionView selectedIndexPaths count = \(collectionView.selectionIndexPaths.count)")
        guard !isApplyingExternalSelection else { return }
        syncSelectionFromCollectionView(reason: "collectionViewDidSelect")
    }

    func collectionView(_ collectionView: NSCollectionView,
                        didDeselectItemsAt indexPaths: Set<IndexPath>) {
        print("[SelectionDebug] NSCollectionView selectedIndexPaths count = \(collectionView.selectionIndexPaths.count)")
        guard !isApplyingExternalSelection else { return }
        syncSelectionFromCollectionView(reason: "collectionViewDidDeselect")
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
    var onFileDrop: (([URL], Int) -> Void)?
    var onInternalDragEnded: (() -> Void)?
    /// Phase 5 — invoked from `menu(for event:)`. Receives the click location
    /// in this view's coordinate space and returns the menu to display, or
    /// `nil` to suppress the menu entirely.
    var onMenuForLocation: ((NSPoint) -> NSMenu?)?

    private let dropOverlayView = NSView()
    private let dropOverlayLabel = NSTextField(labelWithString: "Drop screenshots to import")
    private var isDropHighlightVisible = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureDropOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureDropOverlay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
        window?.makeFirstResponder(self)
        print("[Grid] viewDidMoveToWindow; window=\(window != nil); firstResponder=\(String(describing: window?.firstResponder))")
    }

    override func draggingSession(_ session: NSDraggingSession,
                                  sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : [.copy, .move]
    }

    override func draggingSession(_ session: NSDraggingSession,
                                  endedAt screenPoint: NSPoint,
                                  operation: NSDragOperation) {
        onInternalDragEnded?()
    }

    override func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    private func configureDropOverlay() {
        wantsLayer = true

        dropOverlayView.translatesAutoresizingMaskIntoConstraints = false
        dropOverlayView.wantsLayer = true
        dropOverlayView.layer?.cornerRadius = 12
        dropOverlayView.layer?.borderWidth = 1
        dropOverlayView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.38).cgColor
        dropOverlayView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        dropOverlayView.isHidden = true

        dropOverlayLabel.translatesAutoresizingMaskIntoConstraints = false
        dropOverlayLabel.font = .systemFont(ofSize: 13, weight: .medium)
        dropOverlayLabel.textColor = .secondaryLabelColor
        dropOverlayLabel.alignment = .center

        addSubview(dropOverlayView)
        dropOverlayView.addSubview(dropOverlayLabel)

        NSLayoutConstraint.activate([
            dropOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            dropOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            dropOverlayView.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            dropOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),

            dropOverlayLabel.centerXAnchor.constraint(equalTo: dropOverlayView.centerXAnchor),
            dropOverlayLabel.centerYAnchor.constraint(equalTo: dropOverlayView.centerYAnchor),
        ])
    }

    private func setDropHighlightVisible(_ visible: Bool) {
        guard visible != isDropHighlightVisible else { return }
        isDropHighlightVisible = visible
        dropOverlayView.isHidden = !visible
    }

    private func acceptedDrop(from sender: NSDraggingInfo) -> DragDropController.FileDrop {
        if sender.draggingPasteboard.availableType(from: [InternalScreenshotDrag.pasteboardType]) != nil {
            return DragDropController.FileDrop(supported: [], unsupportedCount: 0)
        }
        return DragDropController.readFileDrop(from: sender.draggingPasteboard)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let drop = acceptedDrop(from: sender)
        guard !drop.isEmpty else {
            setDropHighlightVisible(false)
            return []
        }
        setDropHighlightVisible(drop.hasSupportedFiles)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let drop = acceptedDrop(from: sender)
        setDropHighlightVisible(drop.hasSupportedFiles)
        return drop.isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlightVisible(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDropHighlightVisible(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let drop = acceptedDrop(from: sender)
        setDropHighlightVisible(false)
        guard !drop.isEmpty else { return false }
        onFileDrop?(drop.supported, drop.unsupportedCount)
        return true
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

    /// Phase 5 — right-click. Take focus, hit-test the location to figure out
    /// whether the click landed on an item, and ask the controller's
    /// `onMenuForLocation` callback to build the correct menu. Returning `nil`
    /// suppresses the menu, which is what we want when no callback is wired.
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let local = convert(event.locationInWindow, from: nil)
        return onMenuForLocation?(local)
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
