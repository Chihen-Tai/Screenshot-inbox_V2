import Foundation
import Testing
@testable import ScreenshotInbox

@MainActor
struct ScreenshotInboxStoreTests {
    @Test
    func addScreenshotPublishesLatestAndPreventsDuplicates() {
        let store = ScreenshotInboxStore()
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-05-05 at 10.00.00 AM.png")
        let firstDate = Date(timeIntervalSince1970: 100)

        let first = store.addScreenshot(at: url, createdAt: firstDate)
        let duplicate = store.addScreenshot(at: url, createdAt: Date(timeIntervalSince1970: 200))

        #expect(first != nil)
        #expect(duplicate == nil)
        #expect(store.allItems.count == 1)
        #expect(store.latestScreenshot?.url == url.standardizedFileURL)
        #expect(store.latestItem?.url == url.standardizedFileURL)
        #expect(store.latestUndismissedItem?.url == url.standardizedFileURL)
        #expect(store.latestScreenshot?.createdAt == firstDate)
        #expect(store.latestScreenshot?.isNew == true)
        #expect(store.latestScreenshot?.isDismissed == false)
    }

    @Test
    func importScreenshotIfNeededRejectsDuplicatePathsAndTracksNewUndismissedCount() throws {
        let store = ScreenshotInboxStore()
        let root = try makeRoot()
        let url = root.appendingPathComponent("Screenshot 2026-05-08 at 11.00.00 AM.png")
        try Data([1, 2, 3, 4]).write(to: url)

        let first = store.importScreenshotIfNeeded(url: url, source: .screenshotWatcher)
        let duplicate = store.importScreenshotIfNeeded(url: url, source: .autoImport)

        #expect(first.wasInserted)
        #expect(duplicate.wasInserted == false)
        #expect(store.allItems.count == 1)
        #expect(store.newUndismissedCount == 1)

        if let item = first.item {
            store.dismiss(item)
        }

        #expect(store.newUndismissedCount == 0)
        #expect(store.allItems.count == 1)
    }

    @Test
    func importScreenshotIfNeededIgnoresRegisteredLibraryOriginalURLs() throws {
        let store = ScreenshotInboxStore()
        let root = try makeRoot()
        let url = root.appendingPathComponent("Screenshot 2026-05-08 at 12.00.00 PM.png")
        try Data([1, 2, 3, 4]).write(to: url)

        store.registerExistingLibraryOriginalURLs([url])
        let duplicate = store.importScreenshotIfNeeded(url: url, source: .autoImport)

        #expect(duplicate.wasInserted == false)
        #expect(duplicate.ignoredReason == .duplicate)
        #expect(store.allItems.isEmpty)
        #expect(store.newUndismissedCount == 0)
    }

    @Test
    func importScreenshotIfNeededRejectsMissingAndUnsupportedFiles() throws {
        let store = ScreenshotInboxStore()
        let root = try makeRoot()
        let unsupported = root.appendingPathComponent("Screenshot.gif")
        try Data([1, 2, 3, 4]).write(to: unsupported)
        let missing = root.appendingPathComponent("Screenshot.png")

        #expect(store.importScreenshotIfNeeded(url: unsupported, source: .manualImport).wasInserted == false)
        #expect(store.importScreenshotIfNeeded(url: missing, source: .dragDrop).wasInserted == false)
        #expect(store.allItems.isEmpty)
        #expect(store.newUndismissedCount == 0)
    }

    @Test
    func dismissLatestMarksItemDismissedWithoutRemovingIt() {
        let store = ScreenshotInboxStore()
        let first = URL(fileURLWithPath: "/tmp/first.png")
        let second = URL(fileURLWithPath: "/tmp/second.png")

        _ = store.addScreenshot(at: first, createdAt: Date(timeIntervalSince1970: 100))
        _ = store.addScreenshot(at: second, createdAt: Date(timeIntervalSince1970: 200))

        store.dismissLatestScreenshot()

        #expect(store.allItems.count == 2)
        #expect(store.latestScreenshot?.url == first.standardizedFileURL)
        #expect(store.latestUndismissedItem?.url == first.standardizedFileURL)
        #expect(store.allItems.first(where: { $0.url == second.standardizedFileURL })?.isDismissed == true)
        #expect(store.allItems.first(where: { $0.url == first.standardizedFileURL })?.isDismissed == false)
    }

    @Test
    func dismissItemAndClearDismissedUpdateSectionsWithoutDeletingFiles() {
        let store = ScreenshotInboxStore()
        let first = store.addScreenshot(
            at: URL(fileURLWithPath: "/tmp/first.png"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let second = store.addScreenshot(
            at: URL(fileURLWithPath: "/tmp/second.png"),
            createdAt: Date(timeIntervalSince1970: 200)
        )

        #expect(first != nil)
        #expect(second != nil)
        store.dismiss(first!)

        #expect(store.allItems.count == 2)
        #expect(store.newItems.map(\.url) == [second!.url])
        #expect(store.dismissedItems.map(\.url) == [first!.url])

        store.clearDismissed()

        #expect(store.allItems.map(\.url) == [second!.url])
        #expect(store.dismissedItems.isEmpty)
    }

    @Test
    func dismissCanonicalItemsClearsNewCountForTrashedRichItems() {
        let store = ScreenshotInboxStore()
        let canonicalID = UUID()
        let item = store.addScreenshot(
            at: URL(fileURLWithPath: "/tmp/canonical.png"),
            createdAt: Date(timeIntervalSince1970: 100)
        )

        #expect(item != nil)
        store.updateCanonicalID(for: item!.url, id: canonicalID)
        store.dismissCanonicalItems(ids: [canonicalID])

        #expect(store.newUndismissedCount == 0)
        #expect(store.allItems.first?.isNew == false)
        #expect(store.allItems.first?.isDismissed == true)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
