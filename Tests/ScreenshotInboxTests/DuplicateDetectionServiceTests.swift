import Foundation
import Testing
@testable import ScreenshotInbox

struct DuplicateDetectionServiceTests {
    @Test
    func exactDuplicateGroupsIgnoreTrashedScreenshotsByDefault() {
        let keep = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000001",
            name: "a.png",
            fileHash: "same",
            importedAt: Date(timeIntervalSince1970: 10)
        )
        let duplicate = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000002",
            name: "b.png",
            fileHash: "same",
            importedAt: Date(timeIntervalSince1970: 20)
        )
        let trashed = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000003",
            name: "c.png",
            fileHash: "same",
            isTrashed: true,
            importedAt: Date(timeIntervalSince1970: 30)
        )

        let groups = DuplicateDetectionService.findDuplicateGroups(
            screenshots: [keep, duplicate, trashed],
            imageHashes: [:],
            includeTrashed: false
        )

        #expect(groups.count == 1)
        #expect(groups[0].kind == .exact)
        #expect(groups[0].screenshotUUIDs == [keep.uuidString, duplicate.uuidString])
        #expect(groups[0].recommendedKeepUUID == keep.uuidString)
    }

    @Test
    func similarDuplicateGroupsUseDHashHammingThreshold() {
        let first = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000011",
            name: "first.png",
            importedAt: Date(timeIntervalSince1970: 10)
        )
        let second = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000012",
            name: "second.png",
            importedAt: Date(timeIntervalSince1970: 20)
        )
        let distant = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000013",
            name: "distant.png",
            importedAt: Date(timeIntervalSince1970: 30)
        )

        let groups = DuplicateDetectionService.findDuplicateGroups(
            screenshots: [first, second, distant],
            imageHashes: [
                first.uuidString: ImageHashRecord(screenshotUUID: first.uuidString, algorithm: "dhash64", hash: "0000000000000000", createdAt: Date()),
                second.uuidString: ImageHashRecord(screenshotUUID: second.uuidString, algorithm: "dhash64", hash: "0000000000000003", createdAt: Date()),
                distant.uuidString: ImageHashRecord(screenshotUUID: distant.uuidString, algorithm: "dhash64", hash: "ffffffffffffffff", createdAt: Date())
            ],
            includeTrashed: false,
            similarThreshold: 6
        )

        #expect(groups.count == 1)
        #expect(groups[0].kind == .similar)
        #expect(groups[0].screenshotUUIDs == [first.uuidString, second.uuidString])
    }

    @Test
    func recommendedKeepPrefersFavoriteThenResolutionThenOldest() {
        let old = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000021",
            name: "old.png",
            pixelWidth: 100,
            pixelHeight: 100,
            fileHash: "same",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let larger = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000022",
            name: "larger.png",
            pixelWidth: 200,
            pixelHeight: 200,
            fileHash: "same",
            importedAt: Date(timeIntervalSince1970: 2)
        )
        let favorite = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000023",
            name: "favorite.png",
            pixelWidth: 50,
            pixelHeight: 50,
            fileHash: "same",
            isFavorite: true,
            importedAt: Date(timeIntervalSince1970: 3)
        )

        let groups = DuplicateDetectionService.findDuplicateGroups(
            screenshots: [old, larger, favorite],
            imageHashes: [:],
            includeTrashed: false
        )

        #expect(groups.first?.recommendedKeepUUID == favorite.uuidString)
    }

    private func makeScreenshot(
        uuid: String,
        name: String,
        pixelWidth: Int = 100,
        pixelHeight: Int = 100,
        fileHash: String? = nil,
        isFavorite: Bool = false,
        isTrashed: Bool = false,
        importedAt: Date = Date()
    ) -> Screenshot {
        Screenshot(
            id: UUID(uuidString: uuid)!,
            name: name,
            createdAt: importedAt,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            byteSize: 100,
            format: "PNG",
            tags: [],
            ocrSnippets: [],
            isFavorite: isFavorite,
            isOCRComplete: false,
            thumbnailKind: .document,
            isTrashed: isTrashed,
            libraryPath: "Originals/2026/04/\(uuid).png",
            fileHash: fileHash,
            importedAt: importedAt,
            modifiedAt: importedAt,
            sourceApp: nil,
            sortIndex: 0,
            trashDate: isTrashed ? importedAt : nil
        )
    }
}
