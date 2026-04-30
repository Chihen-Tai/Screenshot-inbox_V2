import SwiftUI
import AppKit

/// Window chrome:
/// - `navigationTitle` shows the current sidebar section ("Inbox", "OCR Pending"…).
/// - `navigationSubtitle` shows a quiet item count, Photos/Mail-style.
/// - The app name lives on the `WindowGroup`, so it stays in the dock/menu
///   bar without competing with the section title.
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(FirstRunOnboarding.preferenceKey) private var hasSeenOnboarding = false

    var body: some View {
        MainSplitView()
            .navigationTitle(appState.displayTitle)
            .navigationSubtitle(itemCountText)
            .toolbar {
                MainToolbarView(
                    searchQuery: $appState.searchQuery,
                    mode: appState.layoutMode,
                    sidebarVisible: $appState.sidebarOverrideVisible,
                    inspectorVisible: $appState.inspectorOverrideVisible,
                    selectedCount: appState.selectedScreenshots.count,
                    isMaintenanceRunning: appState.isMaintenanceRunning,
                    onImport: presentImportPanel,
                    onRefreshOCR: {
                        appState.refreshOCRState()
                        appState.showToast("OCR refreshed", kind: .success)
                    },
                    onRerunOCR: {
                        appState.router.rerunOCR(appState.selectedScreenshots)
                    },
                    onRerunCodeDetection: {
                        appState.router.rerunCodeDetection(appState.selectedScreenshots)
                    },
                    onExportPDF: {
                        appState.router.mergeIntoPDF(appState.selectedScreenshots)
                    },
                    onRevealLibraryFolder: appState.revealLibraryFolder,
                    onRunRulesNow: appState.runRulesNowForSelection,
                    onRebuildThumbnails: appState.rebuildAllThumbnails,
                    onOpenSettings: {
                        SettingsWindowOpener.open(appState: appState)
                    }
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
                // Phase 5: overlay-aware Escape (closes preview/rename first).
                appState.handleEscape()
            }
            // Phase 5 — Quick Look preview sheet.
            .sheet(item: previewBinding) { shot in
                ImagePreviewView(
                    screenshot: shot,
                    thumbnailProvider: appState.thumbnailProvider
                ) {
                    appState.closePreview()
                }
                .environmentObject(appState)
            }
            .sheet(item: ocrTextViewerBinding) { shot in
                OCRTextViewerSheet(screenshot: shot)
                    .environmentObject(appState)
            }
            // Phase 5 — Rename sheet.
            .sheet(item: renameBinding) { shot in
                RenameSheet(originalName: shot.name)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.isTagEditorPresented) {
                TagEntrySheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.isCollectionPickerPresented) {
                CollectionPickerSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.isCollectionRenamePresented) {
                CollectionRenameSheet()
                    .environmentObject(appState)
            }
            .alert("Delete collection '\(appState.collectionDeleteTarget?.name ?? "")'?",
                   isPresented: deleteCollectionBinding) {
                Button("Cancel", role: .cancel) {
                    appState.cancelDeleteCollection()
                }
                Button("Delete Collection", role: .destructive) {
                    appState.confirmDeleteCollection()
                }
            } message: {
                Text("Screenshots will not be deleted. They will only be removed from this collection.")
            }
            .alert(appState.permanentDeleteAlertTitle,
                   isPresented: permanentDeleteBinding) {
                Button("Cancel", role: .cancel) {
                    appState.cancelPermanentDelete()
                }
                Button(appState.permanentDeleteConfirmButtonTitle, role: .destructive) {
                    appState.confirmPermanentDelete()
                }
            } message: {
                Text(appState.permanentDeleteAlertMessage)
            }
            .sheet(isPresented: $appState.isPDFExportSheetPresented) {
                PDFExportSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: onboardingBinding) {
                FirstRunOnboardingView(
                    onContinue: {
                        hasSeenOnboarding = true
                    },
                    onOpenSettings: {
                        hasSeenOnboarding = true
                        SettingsWindowOpener.open(appState: appState)
                    }
                )
            }
            // Phase 5 — bottom-trailing transient banner.
            .overlay(alignment: .bottomTrailing) {
                if let toast = appState.toast {
                    ToastView(message: toast)
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            .animation(.easeOut(duration: 0.18), value: appState.toast?.id)
    }

    /// `.sheet(item:)` needs an `Identifiable` binding. `Screenshot` already
    /// is, so we adapt `previewedScreenshotID` into a binding that yields the
    /// resolved screenshot — and on dismiss, clears the underlying ID.
    private var previewBinding: Binding<Screenshot?> {
        Binding(
            get: { appState.previewedScreenshot },
            set: { newValue in
                if newValue == nil { appState.previewedScreenshotID = nil }
            }
        )
    }

    private var renameBinding: Binding<Screenshot?> {
        Binding(
            get: { appState.renamingScreenshot },
            set: { newValue in
                if newValue == nil { appState.cancelRename() }
            }
        )
    }

    private var ocrTextViewerBinding: Binding<Screenshot?> {
        Binding(
            get: { appState.ocrTextViewerScreenshot },
            set: { newValue in
                if newValue == nil { appState.ocrTextViewerScreenshotID = nil }
            }
        )
    }

    private var itemCountText: String {
        let n = appState.filteredScreenshots.count
        return n == 1 ? "1 item" : "\(n) items"
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasSeenOnboarding },
            set: { isPresented in
                if !isPresented {
                    hasSeenOnboarding = true
                }
            }
        )
    }

    private var deleteCollectionBinding: Binding<Bool> {
        Binding(
            get: { appState.collectionDeleteTarget != nil },
            set: { isPresented in
                if !isPresented {
                    appState.cancelDeleteCollection()
                }
            }
        )
    }

    private var permanentDeleteBinding: Binding<Bool> {
        Binding(
            get: { !appState.permanentDeleteTargetIDs.isEmpty },
            set: { isPresented in
                if !isPresented {
                    appState.cancelPermanentDelete()
                }
            }
        )
    }

    /// Opens an `NSOpenPanel` filtered to the formats the importer can read,
    /// and forwards the resulting URLs to `AppState.importURLs(_:)`.
    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        panel.prompt = "Import"
        panel.message = "Select screenshots to add to your library"

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }
        Task {
            await appState.importURLs(urls)
        }
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
