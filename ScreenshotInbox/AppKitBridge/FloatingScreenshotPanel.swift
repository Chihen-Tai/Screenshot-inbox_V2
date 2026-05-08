import AppKit
import SwiftUI

// MARK: - Show Reason

@MainActor
enum FloatingPreviewShowReason {
    case screenshotCaptured
    case menuBarRequested
    case expandedInboxRequested
    case settingsRequested

    var logDescription: String {
        switch self {
        case .screenshotCaptured:      return "screenshot capture"
        case .menuBarRequested:        return "menu bar"
        case .expandedInboxRequested:  return "expanded inbox"
        case .settingsRequested:       return "settings"
        }
    }
}

enum FloatingPreviewHeaderCount {
    static func title(totalNewCount: Int) -> String? {
        guard totalNewCount > 0 else { return nil }
        return totalNewCount == 1 ? "1 new" : "\(totalNewCount) new"
    }
}

// MARK: - Panel Controller

@MainActor
final class FloatingInboxPanelController: NSObject, NSWindowDelegate {
    static let shared = FloatingInboxPanelController()

    private var panel: NSPanel?
    private weak var appState: AppState?

    var isVisible: Bool { panel?.isVisible == true }

    private override init() {}

    func show(
        items: [ScreenshotItem],
        extraItemCount: Int,
        totalNewCount: Int,
        reason: FloatingPreviewShowReason,
        appState: AppState
    ) {
        self.appState = appState
        let isAlreadyVisible = panel?.isVisible == true

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            print("[FloatingPreview] show requested, existing panel reused")
        } else {
            panel = makePanel()
            self.panel = panel
            print("[FloatingInboxPanel] created")
        }

        panel.contentViewController = NSHostingController(rootView: FloatingInboxPanelView(
            items: items,
            extraItemCount: extraItemCount,
            totalNewCount: totalNewCount,
            appState: appState,
            expandAction: { [weak self, weak appState] in
                print("[FloatingPreview] expand clicked, opening Main Inbox")
                self?.hide()
                appState?.openMainInboxFromFloatingPreview()
            },
            hideAction: { [weak self] in
                print("[FloatingPreview] close clicked")
                self?.hide()
            }
        ))
        // NSHostingController auto-resizes the panel to fit SwiftUI's intrinsic content size.
        // ScrollView/LazyVStack reports near-zero intrinsic height, collapsing the panel.
        // Clamping back to the fixed size after every contentViewController replacement prevents this.
        panel.setContentSize(Self.contentSize())

        print("[FloatingPreviewLayout] item count = \(items.count)")
        print("[FloatingPreviewLayout] mode = unifiedList")
        print("[FloatingPreviewLayout] window size = \(Self.contentSize())")
        print("[FloatingPreviewLayout] content updated without recentering")

        // Suppress focus steal when quietly adding a screenshot to the already-visible panel
        let suppressFocus = isAlreadyVisible
            && reason == .screenshotCaptured
            && appState.screenshotInboxPreferences.keepFloatingPreviewOpenWhileCollecting

        if suppressFocus {
            panel.orderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
        print("[FloatingInboxPanel] shown reason=\(reason.logDescription) items=\(items.count)")
    }

    func hide() {
        panel?.orderOut(nil)
        print("[FloatingPreview] hidden")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func makePanel() -> NSPanel {
        let panel = FloatingInboxPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize()),
            // .nonactivatingPanel: first click delivers directly to controls even
            // when another app is frontmost — without it the first click only
            // activates the app and the button action is never fired.
            // .titled + fullSizeContentView kept for shadow / rounded-corner chrome.
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Hide the native title bar so our SwiftUI header owns the top area.
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = false

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 520, height: 260)
        panel.delegate = self
        panel.center()
        return panel
    }

    private static func contentSize() -> NSSize {
        NSSize(width: 620, height: 380)
    }
}

private final class FloatingInboxPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Panel View

private struct FloatingInboxPanelView: View {
    let items: [ScreenshotItem]
    let extraItemCount: Int
    let totalNewCount: Int
    @ObservedObject var appState: AppState
    let expandAction: () -> Void
    let hideAction: () -> Void

    @State private var selectedItemID: UUID?

    private var store: ScreenshotInboxStore { appState.screenshotInboxStore }

    /// The item keyboard shortcuts act on: the explicitly selected one, or the
    /// first visible one as a fallback.
    private var activeItem: ScreenshotItem? {
        if let id = selectedItemID, let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 56)
            Divider().opacity(0.45)
            if items.isEmpty {
                let _ = print("[FloatingPreview] visible item count = 0")
                let _ = print("[FloatingPreview] rendering empty state")
                emptyStateContent
            } else {
                let _ = print("[FloatingPreview] visible item count = \(items.count)")
                let _ = print("[FloatingPreview] rendering list rows = \(items.count)")
                scrollContent
            }
        }
        // Explicit frame prevents NSHostingController from reporting zero preferred
        // content size (which collapses the panel when contentViewController is replaced).
        .frame(width: 620, height: 380)
        .background(keyboardShortcuts.frame(width: 0, height: 0).opacity(0))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Screenshot Inbox")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let title = FloatingPreviewHeaderCount.title(totalNewCount: totalNewCount) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Button(action: expandAction) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("Open Inbox")

            Button(action: hideAction) {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("Hide")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WindowDragArea())
    }

    // MARK: Content Area

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(items) { item in
                    FloatingScreenshotPanelRow(
                        item: item,
                        isSelected: selectedItemID == item.id,
                        quickLookAction: {
                            print("[FloatingPreview] row double-clicked, quick look id = \(item.id)")
                            quickLook(item)
                        },
                        onSelect: {
                            print("[FloatingPreview] row clicked id = \(item.id)")
                            print("[FloatingPreview] row selected immediately")
                            selectedItemID = item.id
                        }
                    )
                    .onDrag { itemProvider(for: item) }
                    .contextMenu { itemContextMenu(for: item) }
                }
                if extraItemCount > 0 {
                    Text("+\(extraItemCount) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Waiting for screenshots…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("New screenshots will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: Context Menu

    @ViewBuilder
    private func itemContextMenu(for item: ScreenshotItem) -> some View {
        Button("Copy Image") {
            print("[ContextMenu] action = floating.copyImage")
            store.copy(item)
        }
        Button("Copy File") {
            print("[ContextMenu] action = floating.copyFile")
            copyFile(item)
        }
        Button("Reveal in Finder") {
            print("[ContextMenu] action = floating.revealInFinder")
            store.reveal(item)
        }
        Button("Open") {
            print("[ContextMenu] action = floating.open")
            store.open(item)
        }
        Button("Quick Look") {
            print("[ContextMenu] action = floating.quickLook")
            quickLook(item)
        }
        Button("Export as PDF…") {
            print("[ContextMenu] action = floating.exportAsPDF")
            appState.exportInboxItemAsPDF(item)
        }
        Divider()
        Button("Dismiss from Preview") {
            print("[ContextMenu] action = floating.dismiss")
            appState.dismissScreenshotInboxItem(item)
        }
        Divider()
        Button("Move to Trash…", role: .destructive) {
            print("[ContextMenu] action = floating.moveToTrash")
            appState.deleteScreenshotInboxItemWithConfirmation(item)
        }
    }

    private func openInbox(selecting item: ScreenshotItem?) {
        appState.openMainInboxFromFloatingPreview(selecting: item)
    }

    private func quickLook(_ item: ScreenshotItem) {
        QuickLookPreviewController.shared.open(urls: [item.url])
    }

    private func copyFile(_ item: ScreenshotItem) {
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            print("[MissingFile] file missing url = \(item.url.path)")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.url as NSURL])
        print("[Copy] copied 1 item(s)")
    }

    private func itemProvider(for item: ScreenshotItem) -> NSItemProvider {
        print("[FloatingPreview] row drag started id = \(item.id)")
        if FileManager.default.fileExists(atPath: item.url.path) {
            print("[Drag] started with 1 file(s)")
        } else {
            print("[MissingFile] file missing url = \(item.url.path)")
            print("[Drag] started with 0 file(s)")
        }
        return NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
    }

    // MARK: Keyboard Shortcuts

    private var keyboardShortcuts: some View {
        Group {
            Button("Copy") {
                guard let item = activeItem else { return }
                print("[FloatingPanel] shortcut Cmd-C \(item.url.lastPathComponent)")
                store.copy(item)
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Open") {
                guard let item = activeItem else { return }
                print("[FloatingPanel] shortcut Cmd-O \(item.url.lastPathComponent)")
                store.open(item)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Quick Look") {
                guard let item = activeItem else { return }
                print("[FloatingPanel] shortcut Space \(item.url.lastPathComponent)")
                quickLook(item)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Quick Look Return") {
                guard let item = activeItem else { return }
                print("[FloatingPanel] shortcut Return \(item.url.lastPathComponent)")
                quickLook(item)
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("Reveal") {
                guard let item = activeItem else { return }
                print("[FloatingPanel] shortcut Cmd-R \(item.url.lastPathComponent)")
                store.reveal(item)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Dismiss") {
                guard let item = activeItem else { return }
                print("[FloatingPanel] shortcut Delete \(item.url.lastPathComponent)")
                appState.dismissScreenshotInboxItem(item)
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Trash") {
                guard let item = activeItem else { return }
                print("[FloatingPanel] shortcut Cmd-Delete \(item.url.lastPathComponent)")
                appState.deleteScreenshotInboxItemWithConfirmation(item)
            }
            .keyboardShortcut(.delete, modifiers: .command)

            Button("Hide") {
                print("[FloatingPanel] shortcut Escape")
                hideAction()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Open Inbox") {
                print("[FloatingPanel] shortcut Cmd-Return")
                openInbox(selecting: activeItem)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

// MARK: - Drag Region Helper

/// Transparent NSView that makes its area a window-drag region.
/// Placed only behind the header so thumbnails and rows are never
/// captured by window movement — they remain free to start file drags.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragAreaNSView { DragAreaNSView() }
    func updateNSView(_ nsView: DragAreaNSView, context: Context) {}

    final class DragAreaNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

// MARK: - Row

private struct FloatingScreenshotPanelRow: View {
    let item: ScreenshotItem
    let isSelected: Bool
    let quickLookAction: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ScreenshotInboxThumbnail(url: item.url)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if item.isNew {
                    Label("New", systemImage: "sparkle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.blue)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.12)
                      : Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        // onTapGesture fires immediately — no double-click wait because
        // simultaneousGesture below breaks the exclusive-gesture relationship.
        .onTapGesture { onSelect() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { quickLookAction() })
    }
}
