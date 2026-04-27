import AppKit

/// "Is the user typing in a text input right now?"
///
/// Single source of truth for shortcut guards. Cmd-A and Escape behave
/// differently when the search field / any text input owns focus — text
/// fields handle Cmd-A as text select-all and Escape as cancel-edit, and we
/// must not stomp those.
///
/// NSTextField editing routes through a shared NSTextView field editor as
/// the actual first responder, so checking `NSTextView` covers both raw text
/// views and focused text fields. The `FieldEditor` string check is
/// defensive cover for SwiftUI-hosted inputs whose responder isn't a public
/// AppKit subclass.
enum AppKitFocusHelper {
    static func isTextInputFocused(in window: NSWindow? = NSApp.keyWindow) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        if String(describing: type(of: responder)).contains("FieldEditor") { return true }
        return false
    }

    /// Description of the current first responder for debug logs.
    static func describeFirstResponder(in window: NSWindow? = NSApp.keyWindow) -> String {
        guard let responder = window?.firstResponder else { return "nil" }
        return String(describing: type(of: responder))
    }
}
