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

        // ── App menu ───────────────────────────────────────────────────────────

        CommandGroup(replacing: .appInfo) {
            Button("About \(AppReleaseInfo.name)") {
                let credits = NSMutableAttributedString(
                    string: """
                    \(AppReleaseInfo.shortDescription)

                    \(AppReleaseInfo.privacyNote)
                    License: \(AppReleaseInfo.license)
                    \(AppReleaseInfo.copyright)
                    GitHub: \(AppReleaseInfo.repositoryURL)
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

        // ── File menu ──────────────────────────────────────────────────────────

        CommandMenu("File") {
            Button("Open Inbox") {
                AppWindowRouter.shared.openMainInbox(from: .menuBar)
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Show Floating Preview") {
                appState.showLatestScreenshotPanel()
            }

            Divider()

            Button("Import Screenshots…") {
                appState.importFromMenuBar()
            }

            Divider()

            Button("Export Selected…") {
                appState.router.exportOriginals(appState.selectedScreenshots)
            }
            .disabled(appState.selectedScreenshots.isEmpty)
            .keyboardShortcut("e", modifiers: [.command])

            Button(appState.selectedScreenshots.count > 1
                   ? "Combine \(appState.selectedScreenshots.count) Screenshots into PDF…"
                   : "Export as PDF…") {
                appState.router.mergeIntoPDF(appState.selectedScreenshots)
            }
            .disabled(appState.selectedScreenshots.isEmpty)
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button("Reveal in Finder") {
                appState.router.revealInFinder(appState.selectedScreenshots)
            }
            .disabled(appState.selectedScreenshots.isEmpty)
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Move Selected to Trash") {
                appState.router.moveToTrash(appState.selectedScreenshots)
            }
            .disabled(appState.selectedScreenshots.isEmpty)
            .keyboardShortcut(.delete, modifiers: [.command])
        }

        // ── Edit menu ──────────────────────────────────────────────────────────

        CommandGroup(replacing: .undoRedo) {
            Button(appState.undoMenuTitle) {
                if AppKitFocusHelper.isTextInputFocused() {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    return
                }
                appState.performAppUndo()
            }
            .keyboardShortcut("z", modifiers: [.command])

            Button("Redo") {
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
                if AppKitFocusHelper.isTextInputFocused() {
                    NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                    return
                }
                appState.selectAllVisibleScreenshots()
            }
            .keyboardShortcut("a", modifiers: [.command])

            Button("Deselect All") {
                if AppKitFocusHelper.isTextInputFocused() { return }
                appState.clearScreenshotSelection()
            }
            .disabled(appState.selectionCount == 0)
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Rename…") {
                guard let shot = appState.selectedScreenshots.first else { return }
                appState.router.rename(shot)
            }
            .disabled(appState.selectedScreenshots.count != 1)
        }

        // ── View menu ──────────────────────────────────────────────────────────
        // .toolbar and .sidebar placements inject into the system View menu.

        CommandGroup(replacing: .toolbar) {
            Toggle("Show Sidebar", isOn: $appState.sidebarOverrideVisible)

            Toggle("Show Inspector", isOn: $appState.inspectorOverrideVisible)
                .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button("Show Floating Preview") {
                appState.showLatestScreenshotPanel()
            }

            Divider()

            Button("Refresh Library") {
                appState.autoImportService.scanEnabledSources()
            }
        }

        // ── Window menu ────────────────────────────────────────────────────────

        CommandGroup(after: .windowList) {
            Divider()
            Button("Main Inbox") {
                AppWindowRouter.shared.openMainInbox(from: .menuBar)
            }
            Button("Settings") {
                AppWindowRouter.shared.openSettings()
            }
        }

        // ── Help menu ──────────────────────────────────────────────────────────

        CommandGroup(replacing: .help) {
            Button("\(AppReleaseInfo.name) Help") {
                if let url = URL(string: AppReleaseInfo.repositoryURL) {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("GitHub Repository") {
                if let url = URL(string: AppReleaseInfo.repositoryURL) {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Report an Issue") {
                if let url = URL(string: AppReleaseInfo.repositoryIssuesURL) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
