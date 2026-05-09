import Foundation
import Testing
@testable import ScreenshotInbox

struct ReleaseReadinessTests {
    @Test
    func releaseMetadataMatchesAlphaRelease() {
        #expect(AppReleaseInfo.name == "Screenshot Inbox")
        #expect(AppReleaseInfo.version == "0.6.0-alpha")
        #expect(AppReleaseInfo.build == "5")
        #expect(AppReleaseInfo.copyright == "Copyright © 2026 Chihen Tai")
        #expect(AppReleaseInfo.license == "MIT")
        #expect(AppReleaseInfo.shortDescription == "A local-first macOS screenshot organizer.")
        #expect(AppReleaseInfo.privacyNote == "Local-first. No account required.")
    }

    @Test
    func onboardingPreferenceKeyIsStable() {
        #expect(FirstRunOnboarding.preferenceKey == "ScreenshotInbox.hasSeenOnboarding")
    }

    @Test
    func alphaBuildDoesNotKeepHighVolumeDebugPrints() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let bannedSnippetsByFile: [String: [String]] = [
            "ScreenshotInbox/Platform/macOS/MacCodeDetectionService.swift": [
                "[CodeDetection] input image path",
                "[CodeDetection] symbologies",
                "[CodeDetection] result count"
            ],
            "ScreenshotInbox/Platform/macOS/MacOCRService.swift": [
                "[OCR] input image path",
                "[OCR] recognition languages",
                "[OCR] recognitionLevel",
                "[OCR] result length"
            ],
            "ScreenshotInbox/Services/ScreenshotInboxStore.swift": [
                "[Import] source =",
                "[Import] inserted item id",
                "[Import] current item count",
                "[Count] newUndismissedCount",
                "[Dismiss] dismiss called",
                "[ScreenshotInboxStore] linked url",
                "[ScreenshotInboxStore] copied:"
            ],
            "ScreenshotInbox/Services/ImportService.swift": [
                "[Import] done:",
                "[Import] small thumbnail:",
                "[Import] large thumbnail:",
                "[SourceSync] imported managedPath="
            ],
            "ScreenshotInbox/Services/CodeDetectionQueueService.swift": [
                "[CodeDetection] complete"
            ],
            "ScreenshotInbox/Services/OCRQueueService.swift": [
                "[OCR] complete"
            ],
            "ScreenshotInbox/AppKitBridge/SelectionController.swift": [
                "[Selection]",
                "[SelectionDebug]"
            ],
            "ScreenshotInbox/AppKitBridge/ScreenshotCollectionViewController.swift": [
                "[GridLayout]",
                "[Rename] collection item reloaded",
                "[DoubleClick]",
                "[Drag]",
                "[DragSource] libraryPath exists"
            ],
            "ScreenshotInbox/AppKitBridge/ScreenshotCollectionViewLayout.swift": [
                "[GridLayout]"
            ],
            "ScreenshotInbox/Platform/macOS/MacThumbnailProvider.swift": [
                "[ThumbnailProvider] no real thumbnail path",
                "[ThumbnailProvider] using",
                "[ThumbnailProvider] missing thumbnail",
                "[ThumbnailProvider] loaded thumbnail",
                "[ThumbnailProvider] falling back"
            ],
            "ScreenshotInbox/UI/Grid/ScreenshotGridContainer.swift": [
                "[BatchBarDebug]",
                "[GridContainer] background click",
                "[GridContainer] handleEscape"
            ],
            "ScreenshotInbox/UI/Grid/BatchActionBarView.swift": [
                "[BatchBar]"
            ],
            "ScreenshotInbox/UI/MainWindow/MainWindowView.swift": [
                "[MainWindow]"
            ],
            "ScreenshotInbox/App/AppCommands.swift": [
                "[AppCommands]"
            ],
            "ScreenshotInbox/AppKitBridge/ScreenshotInboxWindow.swift": [
                "[MainInbox]"
            ],
            "ScreenshotInbox/AppKitBridge/SettingsWindowController.swift": [
                "[Settings] Settings window shown",
                "[Settings] creating Settings window"
            ],
            "ScreenshotInbox/App/AppWindowRouter.swift": [
                "[Dock]",
                "[Settings] openSettings() called"
            ],
            "ScreenshotInbox/UI/MainWindow/MainSplitView.swift": [
                "[MainSplitView]",
                "[Layout]",
                "[SplitResize]"
            ],
            "ScreenshotInbox/UI/Sidebar/SidebarView.swift": [
                "[Sidebar]",
                "[SidebarDrop]",
                "[CollectionReorder]"
            ],
            "ScreenshotInbox/UI/Sidebar/SidebarDropTargetView.swift": [
                "[SidebarDrop]",
                "[CollectionReorder]"
            ],
            "ScreenshotInbox/UI/Inspector/InspectorView.swift": [
                "[Inspector]"
            ],
            "ScreenshotInbox/Services/ScreenshotActionRouter.swift": [
                "[Router]",
                "[Copy] copied",
                "[Reveal] revealing",
                "[Trash] confirmation shown",
                "[Trash] moved to trash"
            ],
            "ScreenshotInbox/UI/Preview/QuickLookPreviewController.swift": [
                "[QuickLook] opening",
                "[QuickLook] closed"
            ],
            "ScreenshotInbox/Platform/macOS/MacPDFExportService.swift": [
                "[PDFExport] image source used",
                "[PDFExport] debug source copy:"
            ]
        ]

        for (relativePath, bannedSnippets) in bannedSnippetsByFile {
            let source = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            for snippet in bannedSnippets {
                #expect(!source.contains(snippet), "\(relativePath) still contains noisy log: \(snippet)")
            }
        }
    }
}
