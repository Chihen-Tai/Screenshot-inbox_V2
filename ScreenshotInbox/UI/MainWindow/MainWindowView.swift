import SwiftUI
import AppKit

/// Window chrome:
/// - `navigationTitle` shows the current sidebar section ("Inbox", "OCR Pending"…).
/// - `navigationSubtitle` shows a quiet item count, Photos/Mail-style.
/// - The app name lives on the `WindowGroup`, so it stays in the dock/menu
///   bar without competing with the section title.
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        MainSplitView()
            .navigationTitle(appState.displayTitle)
            .navigationSubtitle(itemCountText)
            .toolbar {
                MainToolbarView(
                    searchQuery: $appState.searchQuery,
                    mode: appState.layoutMode,
                    sidebarVisible: $appState.sidebarOverrideVisible,
                    inspectorVisible: $appState.inspectorOverrideVisible
                )
            }
            .frame(
                minWidth: Theme.Layout.minWindowWidth,
                minHeight: Theme.Layout.minWindowHeight
            )
            // Belt-and-braces: SwiftUI's `.frame(minWidth:minHeight:)` does
            // not always propagate to `NSWindow.minSize`, so the user can
            // sometimes drag the window below the SwiftUI floor and break the
            // three-column layout. Push the floor down to AppKit directly.
            .background(
                WindowMinSizeAccessor(
                    minWidth: Theme.Layout.minWindowWidth,
                    minHeight: Theme.Layout.minWindowHeight
                )
            )
            .onAppear {
                print("[MainWindow] onAppear; appState instance=\(ObjectIdentifier(appState))")
                // Drive the window-level shortcut install from SwiftUI's
                // lifecycle. AppKit `viewDidAppear` on a representable's
                // controller is unreliable for this — `.onAppear` always fires.
                appState.installShortcuts()
            }
            // Root-level Escape fallback. SwiftUI surfaces Escape via
            // `.onExitCommand`; AppKit's responder chain has been unreliable
            // here, so this layer guarantees Escape clears grid selection
            // unless a text input wants to cancel its own editing first.
            .onExitCommand {
                print("[MainWindow] onExitCommand; firstResponder=\(AppKitFocusHelper.describeFirstResponder())")
                if AppKitFocusHelper.isTextInputFocused() {
                    NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
                    return
                }
                appState.clearScreenshotSelection()
            }
    }

    private var itemCountText: String {
        let n = appState.filteredScreenshots.count
        return n == 1 ? "1 item" : "\(n) items"
    }
}

/// Pins `NSWindow.minSize` and `contentMinSize` to the supplied dimensions.
/// Hosted as a hidden background view so it can grab the window once it
/// becomes available without changing the visible layout.
private struct WindowMinSizeAccessor: NSViewRepresentable {
    let minWidth: CGFloat
    let minHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { [weak v] in
            guard let window = v?.window else { return }
            let size = NSSize(width: minWidth, height: minHeight)
            window.minSize = size
            window.contentMinSize = size
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            let size = NSSize(width: minWidth, height: minHeight)
            window.minSize = size
            window.contentMinSize = size
        }
    }
}
