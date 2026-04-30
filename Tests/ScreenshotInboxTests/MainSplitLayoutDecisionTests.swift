import Testing
@testable import ScreenshotInbox

struct MainSplitLayoutDecisionTests {
    @Test
    func compactWidthHidesSidebarEvenWhenUserPrefersIt() {
        let decision = MainSplitLayoutDecision(
            width: 720,
            sidebarUserVisible: true,
            inspectorUserVisible: true,
            preferredSidebarWidth: 230,
            preferredInspectorWidth: 330
        )

        #expect(decision.mode == .compact)
        #expect(decision.sidebarVisible == false)
        #expect(decision.inspectorVisible == false)
        #expect(decision.gridWidth == 720)
    }

    @Test
    func mediumWidthShowsSidebarOnlyWhenGridMinimumStillFits() {
        let fits = MainSplitLayoutDecision(
            width: 900,
            sidebarUserVisible: true,
            inspectorUserVisible: false,
            preferredSidebarWidth: 230,
            preferredInspectorWidth: 330
        )

        #expect(fits.mode == .medium)
        #expect(fits.sidebarVisible == true)
        #expect(fits.gridWidth >= Theme.Layout.gridMinWidth)

        let tooNarrow = MainSplitLayoutDecision(
            width: 840,
            sidebarUserVisible: true,
            inspectorUserVisible: false,
            preferredSidebarWidth: 230,
            preferredInspectorWidth: 330
        )

        #expect(tooNarrow.mode == .compact)
        #expect(tooNarrow.sidebarVisible == false)
        #expect(tooNarrow.gridWidth == 840)
    }

    @Test
    func mediumLayoutHidesInspectorBeforeSidebar() {
        let decision = MainSplitLayoutDecision(
            width: 900,
            sidebarUserVisible: true,
            inspectorUserVisible: true,
            preferredSidebarWidth: 230,
            preferredInspectorWidth: 330
        )

        #expect(decision.mode == .medium)
        #expect(decision.sidebarVisible == true)
        #expect(decision.inspectorVisible == false)
        #expect(decision.gridWidth >= Theme.Layout.gridMinWidth)
    }

    @Test
    func wideLayoutRestoresUserPreferredSidebarAndInspectorWhenThereIsSpace() {
        let decision = MainSplitLayoutDecision(
            width: 1300,
            sidebarUserVisible: true,
            inspectorUserVisible: true,
            preferredSidebarWidth: 230,
            preferredInspectorWidth: 330
        )

        #expect(decision.mode == .regular)
        #expect(decision.sidebarVisible == true)
        #expect(decision.inspectorVisible == true)
        #expect(decision.gridWidth >= Theme.Layout.gridMinWidth)
    }
}
