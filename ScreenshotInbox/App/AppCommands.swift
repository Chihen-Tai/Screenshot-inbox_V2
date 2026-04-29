import SwiftUI
import AppKit

/// Menu bar commands for the main window.
///
/// SwiftUI's auto-injected Edit > Select All wires its handler into SwiftUI's
/// own focus system, which never walks the AppKit responder chain — so the
/// AppKit-backed grid never saw Cmd-A. We replace the standard `.pasteboard`
/// group entirely. Cut/Copy/Paste still go through `NSApp.sendAction` so a
/// focused text field handles them. Select All is special-cased: if a text
/// input is focused we forward `selectAll:` to it; otherwise we drive the
/// grid's `SelectionController` directly so Cmd-A works against the grid even
/// though SwiftUI consumes the shortcut before AppKit sees the keyDown.
struct AppCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowOpener.open(appState: appState)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x")

            Button("Copy") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c")

            Button("Paste") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v")

            Button("Select All") {
                print("[AppCommands] Select All fired; instance=\(ObjectIdentifier(appState))")
                print("[AppCommands] firstResponder=\(AppKitFocusHelper.describeFirstResponder())")
                if AppKitFocusHelper.isTextInputFocused() {
                    print("[AppCommands] forwarding selectAll to focused text")
                    NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                    return
                }
                appState.selectAllVisibleScreenshots()
            }
            .keyboardShortcut("a", modifiers: [.command])
        }

        CommandGroup(after: .toolbar) {
            Button(appState.inspectorOverrideVisible ? "Hide Inspector" : "Show Inspector") {
                appState.inspectorOverrideVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
