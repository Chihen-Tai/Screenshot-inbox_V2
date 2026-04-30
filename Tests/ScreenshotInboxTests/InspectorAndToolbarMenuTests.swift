import Testing
@testable import ScreenshotInbox

struct InspectorAndToolbarMenuTests {
    @Test
    func singleSelectionInspectorShowsActionsBeforeMetadata() {
        #expect(InspectorSection.singleSelectionOrder == [
            .preview,
            .actions,
            .ocr,
            .detectedCodes,
            .tags,
            .metadata
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
            .thumbnailSize,
            .sortBy,
            .sortDirection,
            .toggleSidebar,
            .toggleInspector,
            .customizeFilters
        ])
    }

    @Test
    func toolbarMoreMenuContainsWorkingActions() {
        #expect(ToolbarMoreMenuItem.allCases == [
            .refreshOCR,
            .rerunOCR,
            .rerunCodeDetection,
            .share,
            .exportPDF,
            .revealLibraryFolder,
            .runRulesNow,
            .rebuildThumbnails,
            .openSettings
        ])
    }
}
