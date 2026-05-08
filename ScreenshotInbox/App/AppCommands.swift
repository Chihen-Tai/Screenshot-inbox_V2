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

        CommandGroup(replacing: .appInfo) {
            Button("About \(AppReleaseInfo.name)") {
                let credits = NSMutableAttributedString(
                    string: """
                    \(AppReleaseInfo.shortDescription)

                    \(AppReleaseInfo.privacyNote)
                    License: \(AppReleaseInfo.license)
                    \(AppReleaseInfo.copyright)
                    GitHub: \(AppReleaseInfo.repositoryPlaceholder)
                    """,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                    ]
                )
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationName: AppReleaseInfo.name,
                    .applicationVersion: AppReleaseInfo.version,
                    .version: AppReleaseInfo.build,
                    .credits: credits
                ])
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                AppWindowRouter.shared.openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(replacing: .undoRedo) {
            Button(appState.undoMenuTitle) {
                print("[AppCommands] Undo fired; firstResponder=\(AppKitFocusHelper.describeFirstResponder())")
                if AppKitFocusHelper.isTextInputFocused() {
                    print("[AppCommands] forwarding undo to focused text")
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    return
                }
                appState.performAppUndo()
            }
            .keyboardShortcut("z", modifiers: [.command])

            Button("Redo") {
                print("[AppCommands] Redo fired; firstResponder=\(AppKitFocusHelper.describeFirstResponder())")
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if AppKitFocusHelper.isTextInputFocused() {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    return
                }
                appState.cutSelectedScreenshotsToPasteboard()
            }
            .keyboardShortcut("x")

            Button("Copy") {
                if AppKitFocusHelper.isTextInputFocused() {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    return
                }
                appState.copySelectedScreenshotsToPasteboard()
            }
            .keyboardShortcut("c")

            Button("Paste") {
                if AppKitFocusHelper.isTextInputFocused() {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    return
                }
                appState.pasteClipboardIntoInbox()
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

        CommandGroup(after: .pasteboard) {
            Button("Reveal in Finder") {
                let shots = appState.selectedScreenshots
                guard !shots.isEmpty else { return }
                print("[AppCommands] Reveal in Finder fired count=\(shots.count)")
                appState.router.revealInFinder(shots)
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Export Original…") {
                let shots = appState.selectedScreenshots
                guard !shots.isEmpty else { return }
                print("[AppCommands] Export Original fired count=\(shots.count)")
                appState.router.exportOriginals(shots)
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(appState.selectedScreenshots.isEmpty)

            Button(appState.selectedScreenshots.count > 1
                   ? "Combine \(appState.selectedScreenshots.count) Screenshots into PDF…"
                   : "Export as PDF…") {
                let shots = appState.selectedScreenshots
                guard !shots.isEmpty else { return }
                print("[AppCommands] Combine into PDF fired count=\(shots.count)")
                appState.router.mergeIntoPDF(shots)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.selectedScreenshots.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Button(appState.inspectorOverrideVisible ? "Hide Inspector" : "Show Inspector") {
                appState.inspectorOverrideVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
