import Foundation
import Testing
@testable import ScreenshotInbox

@MainActor
struct SelectionControllerTests {
    @Test
    func setSelectedIDsReplacesCanonicalSelectionWithFullSnapshot() {
        let controller = SelectionController()
        let first = UUID()
        let second = UUID()
        let stale = UUID()

        controller.selectAll(in: [first, stale])
        controller.setSelectedIDs([first, second], source: "test")

        #expect(controller.selectedIDs == [first, second])
        #expect(controller.count == 2)
    }
}
