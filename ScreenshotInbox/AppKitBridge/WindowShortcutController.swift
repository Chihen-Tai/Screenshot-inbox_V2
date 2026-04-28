import AppKit

/// Window-scoped Cmd-A / Escape handler.
///
/// Phase 4 fix v3: SwiftUI's command system + AppKit's responder chain were
/// both starving the grid of these shortcuts even with `selectAll(_:)` and
/// `cancelOperation(_:)` overrides. A local `NSEvent` monitor catches the
/// keyDown before SwiftUI gets a chance to swallow it.
///
/// Behavior contract:
/// - Only fires when the provided window is key and is the event's window.
/// - Defers to text inputs (search field, NSTextField field editor) so Cmd-A
///   still selects text and Escape still cancels editing in-place.
/// - Returns `nil` from the monitor to consume the event when handled, so
///   AppKit doesn't double-dispatch a beep / second handler.
final class WindowShortcutController {
    var onSelectAll: (() -> Void)?
    var onClearSelection: (() -> Void)?
    /// Phase 5 — Delete / Forward-Delete (keyCodes 51 / 117). Mock trash.
    var onTrash: (() -> Void)?
    /// Phase 5 — Space (keyCode 49). Toggles preview overlay.
    var onPreview: (() -> Void)?
    /// Phase 5 — Return / Enter (keyCode 36). Opens rename sheet.
    var onRename: (() -> Void)?

    private var monitor: Any?
    private var windowProvider: (() -> NSWindow?)?

    func install(for windowProvider: @escaping () -> NSWindow?) {
        // Idempotent — re-installing replaces the previous monitor instead
        // of stacking handlers that all consume the same keyDown.
        uninstall()
        self.windowProvider = windowProvider

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        windowProvider = nil
    }

    deinit { uninstall() }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) -> NSEvent? {
        print("[Shortcut] monitor fired")
        guard let window = windowProvider?() else {
            print("[Shortcut] no window available; passing event through")
            return event
        }
        guard window.isKeyWindow, event.window === window else {
            print("[Shortcut] event not for our key window; passing through")
            return event
        }

        let firstResponder = window.firstResponder
        let key = event.charactersIgnoringModifiers
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        print("[Shortcut] keyCode:", event.keyCode)
        print("[Shortcut] chars:", key ?? "nil")
        print("[Shortcut] flags:", flags)
        print("[Shortcut] firstResponder:", String(describing: firstResponder))
        let isTextInput = isTextInputFirstResponder(firstResponder)
        print("[Shortcut] isTextInput:", isTextInput)

        if isTextInput {
            return event
        }

        let isCommandOnly = flags.contains(.command)
            && !flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.control)

        if isCommandOnly, key?.lowercased() == "a" {
            print("[Shortcut] Cmd+A detected, calling onSelectAll")
            onSelectAll?()
            return nil
        }

        // Escape: keyCode 53, or ESC character (\u{1b}).
        if event.keyCode == 53 || key == "\u{1b}" {
            print("[Shortcut] Escape detected, calling onClearSelection")
            onClearSelection?()
            return nil
        }

        // Phase 5 single-key shortcuts. Only fire on bare keys (no modifiers)
        // so they don't fight Cmd-Delete / Shift-Space etc.
        let isPlainKey = flags.isEmpty || flags == .function

        // Delete / Forward-Delete → mock trash.
        if isPlainKey, event.keyCode == 51 || event.keyCode == 117 {
            print("[Shortcut] Delete detected, calling onTrash")
            onTrash?()
            return nil
        }

        // Space → toggle preview.
        if isPlainKey, event.keyCode == 49 {
            print("[Shortcut] Space detected, calling onPreview")
            onPreview?()
            return nil
        }

        // Return / Enter → rename.
        if isPlainKey, event.keyCode == 36 {
            print("[Shortcut] Return detected, calling onRename")
            onRename?()
            return nil
        }

        return event
    }

    /// NSTextField editing routes through a shared NSTextView field editor —
    /// checking NSTextView covers both raw text views and focused text fields.
    /// We also string-match `FieldEditor` defensively for SwiftUI-hosted
    /// inputs whose responder isn't a public AppKit class.
    private func isTextInputFirstResponder(_ responder: NSResponder?) -> Bool {
        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        if let responder, String(describing: type(of: responder)).contains("FieldEditor") {
            return true
        }
        return false
    }
}
