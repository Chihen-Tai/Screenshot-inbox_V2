import Testing
@testable import ScreenshotInbox

struct InspectorAndToolbarMenuTests {
    @Test
    func singleSelectionInspectorShowsActionsBeforeMetadata() {
        #expect(InspectorSection.singleSelectionOrder == [
            .preview,
            .actions,
            .metadata,
            .ocr,
            .detectedCodes,
            .tags
        ])
    }

    @Test
    func multiSelectionInspectorKeepsBatchActionsNearTheTop() {
        #expect(InspectorSection.multiSelectionOrder == [
            .selectionSummary,
            .actions,
            .commonTags
        ])
    }

    @Test
    func toolbarViewOptionsMenuContainsOnlyWorkingItems() {
        #expect(ToolbarViewOptionsMenuItem.allCases == [
            .toggleSidebar,
            .toggleInspector
        ])
    }

    @Test
    func toolbarMoreMenuContainsWorkingActions() {
        #expect(ToolbarMoreMenuItem.allCases == [
            .refreshOCR,
            .rerunOCR,
            .rerunCodeDetection,
            .exportPDF,
            .revealLibraryFolder,
            .runRulesNow,
            .rebuildThumbnails,
            .openSettings
        ])
    }
}
