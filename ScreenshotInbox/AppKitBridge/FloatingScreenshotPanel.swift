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
        let newSize = Self.contentSize(itemCount: items.count)

        let panel: NSPanel
        let isNewPanel: Bool
        if let existing = self.panel {
            panel = existing
            isNewPanel = false
        } else {
            panel = makePanel()
            self.panel = panel
            isNewPanel = true
        }

        // Capture frame before NSHostingController can mutate it.
        let frameBeforeUpdate = panel.frame

        panel.contentViewController = NSHostingController(rootView: FloatingInboxPanelView(
            items: items,
            extraItemCount: extraItemCount,
            totalNewCount: totalNewCount,
            panelSize: CGSize(width: newSize.width, height: newSize.height),
            appState: appState,
            expandAction: { [weak self, weak appState] in
                self?.hide()
                appState?.openMainInboxFromFloatingPreview()
            },
            hideAction: { [weak self] in
                self?.hide()
            }
        ))

        if isAlreadyVisible && !isNewPanel {
            // Already visible: resize while keeping the top-right corner fixed so the
            // panel doesn't jump when a second or third screenshot arrives.
            let newFrame = NSRect(
                x: frameBeforeUpdate.maxX - newSize.width,
                y: frameBeforeUpdate.maxY - newSize.height,
                width: newSize.width,
                height: newSize.height
            )
            panel.setFrame(newFrame, display: true, animate: false)
        } else {
            // First show or after hide: size correctly then center.
            // setContentSize prevents NSHostingController zero-height collapse.
            panel.setContentSize(newSize)
            panel.center()
        }

        // Suppress focus steal when quietly appending to the already-visible panel.
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
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // Called when user clicks the native red close button.
    // Returns false so the panel is only hidden (orderOut), not destroyed.
    // isReleasedWhenClosed = false ensures the panel can be reshown later.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func makePanel() -> NSPanel {
        let panel = FloatingInboxPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize(itemCount: 0)),
            // .nonactivatingPanel: first click hits controls even when another app is frontmost.
            // .titled + .closable: provides the native red close button in the window chrome.
            // .fullSizeContentView: SwiftUI content fills the full frame including title bar area.
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Show only the close button; hide miniaturize and zoom.
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Keep panel alive after windowShouldClose → hide() so it can be reshown.
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 480, height: 220)
        panel.delegate = self
        // Centering happens in show() after the correct content size is set.
        return panel
    }

    /// Height varies with item count; width is fixed at 560pt.
    private static func contentSize(itemCount: Int) -> NSSize {
        let height: CGFloat
        switch itemCount {
        case 0:  height = 220
        case 1:  height = 240
        case 2:  height = 320
        default: height = 380
        }
        return NSSize(width: 560, height: height)
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
    /// Explicit size passed from the controller so the SwiftUI root frame matches
    /// the panel size. Without this, ScrollView + LazyVStack reports near-zero
    /// intrinsic height and NSHostingController collapses the panel on every
    /// contentViewController reassignment.
    let panelSize: CGSize
    @ObservedObject var appState: AppState
    let expandAction: () -> Void
    let hideAction: () -> Void   // used by Escape keyboard shortcut only

    @State private var selectedItemID: UUID?

    private var store: ScreenshotInboxStore { appState.screenshotInboxStore }

    private var activeItem: ScreenshotItem? {
        if let id = selectedItemID, let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 44)
            Divider().opacity(0.45)
            if items.isEmpty {
                emptyStateContent
            } else {
                scrollContent
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
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
            // No custom close button — the native red traffic-light button is used.
        }
        // Leading padding clears the traffic-light zone (close button sits at ~x=8).
        .padding(.leading, 56)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
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
                            quickLook(item)
                        },
                        onSelect: {
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
        Button("Copy Image") { store.copy(item) }
        Button("Copy File") { copyFile(item) }
        Button("Reveal in Finder") { store.reveal(item) }
        Button("Open") { store.open(item) }
        Button("Quick Look") { quickLook(item) }
        Button("Export as PDF…") { appState.exportInboxItemAsPDF(item) }
        Divider()
        Button("Dismiss from Preview") { appState.dismissScreenshotInboxItem(item) }
        Divider()
        Button("Move to Trash…", role: .destructive) { appState.deleteScreenshotInboxItemWithConfirmation(item) }
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
    }

    private func itemProvider(for item: ScreenshotItem) -> NSItemProvider {
        if !FileManager.default.fileExists(atPath: item.url.path) {
            print("[MissingFile] file missing url = \(item.url.path)")
        }
        return NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
    }

    // MARK: Keyboard Shortcuts

    private var keyboardShortcuts: some View {
        Group {
            Button("Copy") {
                guard let item = activeItem else { return }
                store.copy(item)
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Open") {
                guard let item = activeItem else { return }
                store.open(item)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Quick Look") {
                guard let item = activeItem else { return }
                quickLook(item)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Quick Look Return") {
                guard let item = activeItem else { return }
                quickLook(item)
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("Reveal") {
                guard let item = activeItem else { return }
                store.reveal(item)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Dismiss") {
                guard let item = activeItem else { return }
                appState.dismissScreenshotInboxItem(item)
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Trash") {
                guard let item = activeItem else { return }
                appState.deleteScreenshotInboxItemWithConfirmation(item)
            }
            .keyboardShortcut(.delete, modifiers: .command)

            Button("Hide") {
                hideAction()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Open Inbox") {
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
        HStack(spacing: 10) {
            ScreenshotInboxThumbnail(url: item.url)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
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
        .padding(.horizontal, 12)
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
        .onTapGesture { onSelect() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { quickLookAction() })
    }
}
