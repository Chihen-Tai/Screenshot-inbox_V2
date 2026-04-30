import AppKit

/// Phase 5: builds the right-click `NSMenu` for grid items and empty grid
/// background. The single dispatch point for what each menu does is
/// `ScreenshotActionRouter`; this controller is purely a menu factory plus a
/// thin `@objc` invoker so AppKit can target it.
///
/// Selection-sync rule (mirrors Finder) is delegated to the router via
/// `syncSelectionForContextMenu(rightClickedID:)` — call it BEFORE asking for
/// the item menu so the menu's targets reflect the post-sync selection.
@MainActor
final class ContextMenuController {
    private unowned let appState: AppState
    private unowned let router: ScreenshotActionRouter
    private let invoker: MenuActionInvoker

    init(appState: AppState, router: ScreenshotActionRouter) {
        self.appState = appState
        self.router = router
        self.invoker = MenuActionInvoker(router: router, appState: appState)
    }

    // MARK: - Item menu

    /// Right-click on a grid item. The caller must have already invoked
    /// `router.syncSelectionForContextMenu(rightClickedID:)`; this menu
    /// operates on `appState.selectedScreenshots` as it stands.
    func itemMenu() -> NSMenu {
        let targets = appState.selectedScreenshots
        let menu = NSMenu()
        menu.autoenablesItems = false

        let n = targets.count
        let isTrashView = appState.sidebarSelection == .trash

        if isTrashView {
            add(menu, title: n > 1 ? "Restore Selected" : "Restore",
                key: .restoreFromTrash)
            add(menu, title: n > 1 ? "Delete Permanently Selected" : "Delete Permanently",
                key: .deletePermanently)
            menu.addItem(.separator())
            add(menu, title: "Reveal in Finder",              key: .revealInFinder)
            add(menu, title: "Open",                          key: .open)
            return menu
        }

        add(menu, title: "Open",                              key: .open)
        add(menu, title: "Quick Look",                        key: .quickLook,
            keyEquivalent: " ", modifiers: [])
        add(menu, title: "Reveal in Finder",                  key: .revealInFinder)
        if n == 1 {
            add(menu, title: "Rename",                        key: .rename,
                keyEquivalent: "\r", modifiers: [])
        }
        menu.addItem(.separator())

        add(menu,
            title: favoriteTitle(for: targets),
            key: .toggleFavorite)
        add(menu, title: n > 1 ? "Add Tag to \(n) Screenshots" : "Add Tag",
            key: .addTag)
        add(menu, title: n > 1 ? "Add \(n) Screenshots to Collection" : "Add to Collection",
            key: .moveToCollection)
        menu.addItem(.separator())

        add(menu, title: n > 1 ? "Copy \(n) Images" : "Copy Image",
            key: .copyImage)
        add(menu, title: n > 1 ? "Copy \(n) Files" : "Copy File",
            key: .copyFile)
        add(menu, title: "Copy File Path",
            key: .copyFilePath)
        add(menu, title: "Copy Markdown Reference",
            key: .copyMarkdownReference)
        add(menu, title: n > 1 ? "Copy OCR Text from \(n) Screenshots" : "Copy OCR Text",
            key: .copyOCRText)
        if n == 1 {
            let hasOCRText = targets.first?.isOCRComplete == true && targets.first?.ocrSnippets.isEmpty == false
            add(menu, title: "View OCR Text", key: .viewOCRText, enabled: hasOCRText)
        }
        add(menu, title: n > 1 ? "Re-run OCR for \(n) Screenshots" : "Re-run OCR",
            key: .rerunOCR)
        if n == 1 {
            let codes = targets.first.map { appState.detectedCodes(for: $0) } ?? []
            if codes.contains(where: \.isURL) {
                add(menu, title: "Open Detected Link", key: .openDetectedLink)
            }
            if !codes.isEmpty {
                add(menu, title: codes.first?.isURL == true ? "Copy Detected Link" : "Copy Detected Text",
                    key: .copyDetectedLink)
            }
        }
        add(menu, title: n > 1 ? "Re-detect Codes for \(n) Screenshots" : "Re-detect Codes",
            key: .rerunCodeDetection)
        add(menu, title: n > 1 ? "Merge \(n) Screenshots into PDF" : "Export as PDF",
            key: .mergeIntoPDF)
        add(menu, title: "Export Originals…",
            key: .exportOriginals)
        add(menu, title: "Export OCR as Markdown…",
            key: .exportOCRMarkdown)
        add(menu, title: "Share…",
            key: .share)
        menu.addItem(.separator())

        add(menu,
            title: n > 1 ? "Move \(n) Screenshots to Trash" : "Move to Trash",
            key: .moveToTrash,
            keyEquivalent: "\u{8}", modifiers: [])

        return menu
    }

    // MARK: - Empty-area menu

    /// Right-click on grid background.
    func emptyAreaMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        add(menu, title: "Import Screenshots…", key: .importScreenshots)
        add(menu, title: "New Collection",      key: .newCollection)
        menu.addItem(.separator())
        add(menu, title: "Select All",          key: .selectAll,
            keyEquivalent: "a", modifiers: .command)
        if !appState.selection.isEmpty {
            add(menu, title: "Clear Selection", key: .clearSelection,
                keyEquivalent: "\u{1b}", modifiers: [])
        }
        return menu
    }

    // MARK: - Builder helper

    private func add(_ menu: NSMenu,
                     title: String,
                     key: MenuActionKey,
                     keyEquivalent: String = "",
                     modifiers: NSEvent.ModifierFlags = [],
                     enabled: Bool = true) {
        let item = NSMenuItem(
            title: title,
            action: #selector(MenuActionInvoker.invoke(_:)),
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = modifiers
        item.target = invoker
        item.representedObject = key.rawValue
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private func favoriteTitle(for targets: [Screenshot]) -> String {
        let n = targets.count
        let shouldFavorite = targets.contains { !$0.isFavorite }
        if shouldFavorite {
            return n > 1 ? "Add \(n) Screenshots to Favorites" : "Add to Favorites"
        }
        return n > 1 ? "Remove \(n) Screenshots from Favorites" : "Remove from Favorites"
    }
}

// MARK: - Action keys

/// String-keyed identifiers stored in each `NSMenuItem.representedObject`.
/// `String` is required because `representedObject` must be `Any` and survive
/// the AppKit boundary; raw enums conform via `RawRepresentable`.
private enum MenuActionKey: String {
    case open
    case quickLook
    case revealInFinder
    case rename
    case addTag
    case moveToCollection
    case copyImage
    case copyFile
    case copyFilePath
    case copyMarkdownReference
    case copyOCRText
    case viewOCRText
    case rerunOCR
    case openDetectedLink
    case copyDetectedLink
    case rerunCodeDetection
    case mergeIntoPDF
    case exportOriginals
    case exportOCRMarkdown
    case share
    case moveToTrash
    case toggleFavorite
    case restoreFromTrash
    case deletePermanently
    case importScreenshots
    case newCollection
    case selectAll
    case clearSelection
}

// MARK: - Invoker

/// `NSObject` subclass so AppKit menu items can target it via `#selector`.
/// All menu items funnel through `invoke(_:)`, then dispatch to the router on
/// the main actor against the current selection snapshot.
@MainActor
private final class MenuActionInvoker: NSObject {
    private unowned let router: ScreenshotActionRouter
    private unowned let appState: AppState

    init(router: ScreenshotActionRouter, appState: AppState) {
        self.router = router
        self.appState = appState
    }

    @objc func invoke(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = MenuActionKey(rawValue: raw) else {
            print("[ContextMenu] invoke: unknown representedObject")
            return
        }
        let targets = appState.selectedScreenshots
        print("[ContextMenu] invoke key=\(key.rawValue) targets=\(targets.count)")

        switch key {
        case .open:              router.open(targets)
        case .quickLook:         router.quickLook(targets)
        case .revealInFinder:    router.revealInFinder(targets)
        case .rename:
            if let one = targets.first { router.rename(one) }
        case .addTag:            router.addTag(targets)
        case .moveToCollection:  router.moveToCollection(targets)
        case .copyImage:         router.copyImage(targets)
        case .copyFile:          router.copyFiles(targets)
        case .copyFilePath:      router.copyFilePaths(targets)
        case .copyMarkdownReference: router.copyMarkdownReference(targets)
        case .copyOCRText:       router.copyOCRText(targets)
        case .viewOCRText:       router.viewOCRText(targets)
        case .rerunOCR:          router.rerunOCR(targets)
        case .openDetectedLink:  router.openDetectedLink(targets)
        case .copyDetectedLink:  router.copyDetectedLink(targets)
        case .rerunCodeDetection: router.rerunCodeDetection(targets)
        case .mergeIntoPDF:      router.mergeIntoPDF(targets)
        case .exportOriginals:   router.exportOriginals(targets)
        case .exportOCRMarkdown: router.exportOCRMarkdown(targets)
        case .share:             router.share(targets)
        case .moveToTrash:       router.moveToTrash(targets)
        case .toggleFavorite:    router.toggleFavorite(targets)
        case .restoreFromTrash:  router.restoreFromTrash(targets)
        case .deletePermanently: router.deletePermanently(targets)
        case .importScreenshots: router.importScreenshots()
        case .newCollection:     router.newCollection()
        case .selectAll:         router.selectAll()
        case .clearSelection:    router.clearSelection()
        }
    }
}
