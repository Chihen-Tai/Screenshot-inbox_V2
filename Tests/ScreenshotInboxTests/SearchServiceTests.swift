import Foundation
import Testing
@testable import ScreenshotInbox

struct SearchServiceTests {
    private let service = SearchService()

    @Test
    func searchesFilenameOCRChineseTagsCollectionsAndQRPayloads() {
        let chemistry = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000101",
            name: "Benzene Notes.png",
            tags: ["chemistry"],
            ocrSnippets: ["苯環 反應", "Nitration notes"]
        )
        let qr = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000102",
            name: "Link.png"
        )
        let screenshots = [chemistry, qr]
        let collections = [chemistry.id: ["Papers"]]
        let codes = [
            qr.uuidString: [
                DetectedCode(
                    id: 1,
                    screenshotUUID: qr.uuidString,
                    symbology: "QR",
                    payload: "https://example.com/invite",
                    isURL: true,
                    createdAt: Date(),
                    updatedAt: nil
                )
            ]
        ]

        #expect(filter(screenshots, "benzene", collections, codes) == [chemistry])
        #expect(filter(screenshots, "苯環", collections, codes) == [chemistry])
        #expect(filter(screenshots, "tag:chemistry", collections, codes) == [chemistry])
        #expect(filter(screenshots, "collection:Papers", collections, codes) == [chemistry])
        #expect(filter(screenshots, "invite", collections, codes) == [qr])
    }

    @Test
    func appliesLightweightQueryFilters() {
        let favorite = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000111",
            name: "Favorite.png",
            isFavorite: true,
            sourceApp: "Downloads"
        )
        let trashed = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000112",
            name: "Trashed.png",
            isTrashed: true
        )
        let pendingOCR = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000113",
            name: "No OCR.png",
            isOCRComplete: false
        )
        let qr = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000114",
            name: "QR.jpg",
            format: "JPG"
        )
        let screenshots = [favorite, trashed, pendingOCR, qr]
        let codes = [
            qr.uuidString: [
                DetectedCode(
                    id: 1,
                    screenshotUUID: qr.uuidString,
                    symbology: "QR",
                    payload: "otpauth://totp/example",
                    isURL: false,
                    createdAt: Date(),
                    updatedAt: nil
                )
            ]
        ]

        #expect(filter(screenshots, "is:favorite", [:], codes) == [favorite])
        #expect(filter(screenshots, "is:trashed", [:], codes) == [trashed])
        #expect(filter(screenshots, "has:ocr", [:], codes) == [favorite, trashed, qr])
        #expect(filter(screenshots, "has:qr", [:], codes) == [qr])
        #expect(filter(screenshots, "type:jpg", [:], codes) == [qr])
        #expect(filter(screenshots, "source:downloads", [:], codes) == [favorite])
    }

    @Test
    func combinesTextAndStructuredFilters() {
        let match = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000121",
            name: "Lab Notes.png",
            tags: ["chemistry"],
            ocrSnippets: ["benzene"]
        )
        let wrongTag = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000122",
            name: "Lab Notes.png",
            tags: ["physics"],
            ocrSnippets: ["benzene"]
        )

        #expect(filter([match, wrongTag], "benzene tag:chemistry", [:], [:]) == [match])
    }

    private func filter(
        _ screenshots: [Screenshot],
        _ query: String,
        _ collections: [UUID: [String]],
        _ codes: [String: [DetectedCode]]
    ) -> [Screenshot] {
        service.filter(
            screenshots,
            query: query,
            collectionNamesByScreenshotID: collections,
            detectedCodesByScreenshotID: codes
        )
    }

    private func makeScreenshot(
        uuid: String,
        name: String,
        format: String = "PNG",
        tags: [String] = [],
        ocrSnippets: [String] = ["recognized text"],
        isFavorite: Bool = false,
        isOCRComplete: Bool = true,
        isTrashed: Bool = false,
        sourceApp: String? = nil
    ) -> Screenshot {
        let id = UUID(uuidString: uuid)!
        let now = Date()
        return Screenshot(
            id: id,
            name: name,
            createdAt: now,
            pixelWidth: 100,
            pixelHeight: 100,
            byteSize: 100,
            format: format,
            tags: tags,
            ocrSnippets: ocrSnippets,
            isFavorite: isFavorite,
            isOCRComplete: isOCRComplete,
            thumbnailKind: .document,
            isTrashed: isTrashed,
            libraryPath: "Originals/2026/04/\(uuid).\(format.lowercased())",
            fileHash: nil,
            importedAt: now,
            modifiedAt: now,
            sourceApp: sourceApp,
            sortIndex: 0,
            trashDate: isTrashed ? now : nil
        )
    }
}
