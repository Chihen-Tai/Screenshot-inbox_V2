import Foundation

/// Visual style of a mock thumbnail. Phase 2 only.
/// Phase 3 replaces this with real thumbnail file URLs sourced from disk.
enum ThumbnailKind: String, CaseIterable, Hashable {
    case document, code, lectureSlide, chat, chart, paper, terminal, notes, uiMockup, table
}

struct Screenshot: Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var byteSize: Int
    var format: String
    var tags: [String]
    var ocrSnippets: [String]
    var isFavorite: Bool
    var isOCRComplete: Bool
    var thumbnailKind: ThumbnailKind
    /// Phase 5 mock trash. `true` hides the screenshot from normal views and
    /// surfaces it under the Trash sidebar item. No real file ops yet.
    var isTrashed: Bool = false
}

extension Screenshot {
    /// Mock library used by the Phase 2 prototype.
    /// TODO: remove once `LibraryService` provides real screenshots from SQLite.
    static let mocks: [Screenshot] = {
        let now = Date()
        func ago(_ minutes: Int) -> Date { now.addingTimeInterval(-Double(minutes) * 60) }
        return [
            Screenshot(id: UUID(), name: "EAS Lecture 03.png",
                       createdAt: ago(45),
                       pixelWidth: 2880, pixelHeight: 1800, byteSize: 1_240_000, format: "PNG",
                       tags: ["lecture", "chemistry", "reaction"],
                       ocrSnippets: ["Electrophilic Aromatic Substitution",
                                     "Nitration of Benzene",
                                     "HNO3 / H2SO4 → NO2"],
                       isFavorite: true, isOCRComplete: true, thumbnailKind: .lectureSlide),
            Screenshot(id: UUID(), name: "Pull Request — selection.ts.png",
                       createdAt: ago(120),
                       pixelWidth: 2560, pixelHeight: 1600, byteSize: 980_000, format: "PNG",
                       tags: ["code", "review"],
                       ocrSnippets: ["function applySelection(state, ids) {",
                                     "  return { ...state, selected: ids }",
                                     "}"],
                       isFavorite: false, isOCRComplete: true, thumbnailKind: .code),
            Screenshot(id: UUID(), name: "Anomalous Hall Effect.png",
                       createdAt: ago(300),
                       pixelWidth: 3024, pixelHeight: 1964, byteSize: 1_640_000, format: "PNG",
                       tags: ["paper", "physics"],
                       ocrSnippets: ["Anomalous Hall Effect in Topological Materials",
                                     "Nature Physics, Vol. 19, 2024"],
                       isFavorite: false, isOCRComplete: true, thumbnailKind: .paper),
            Screenshot(id: UUID(), name: "Slack — design review.png",
                       createdAt: ago(600),
                       pixelWidth: 1920, pixelHeight: 1080, byteSize: 540_000, format: "PNG",
                       tags: ["chat"],
                       ocrSnippets: ["@aery — can we tighten the inspector spacing?",
                                     "Yes, +1 to softer dividers."],
                       isFavorite: false, isOCRComplete: true, thumbnailKind: .chat),
            Screenshot(id: UUID(), name: "Q1 retention chart.png",
                       createdAt: ago(1440),
                       pixelWidth: 2200, pixelHeight: 1400, byteSize: 720_000, format: "PNG",
                       tags: ["chart", "analytics"],
                       ocrSnippets: ["D7 retention", "+4.2% vs last quarter"],
                       isFavorite: true, isOCRComplete: true, thumbnailKind: .chart),
            Screenshot(id: UUID(), name: "Inbox V2 mockup.png",
                       createdAt: ago(2880),
                       pixelWidth: 2880, pixelHeight: 1800, byteSize: 1_180_000, format: "PNG",
                       tags: ["ui", "mockup"],
                       ocrSnippets: ["Library", "Inbox", "Search screenshots"],
                       isFavorite: false, isOCRComplete: true, thumbnailKind: .uiMockup),
            Screenshot(id: UUID(), name: "swift build output.png",
                       createdAt: ago(4320),
                       pixelWidth: 1920, pixelHeight: 1080, byteSize: 460_000, format: "PNG",
                       tags: ["terminal"],
                       ocrSnippets: ["[88/88] Linking ScreenshotInbox", "Build complete!"],
                       isFavorite: false, isOCRComplete: false, thumbnailKind: .terminal),
            Screenshot(id: UUID(), name: "Reading notes.png",
                       createdAt: ago(5760),
                       pixelWidth: 2400, pixelHeight: 1500, byteSize: 660_000, format: "PNG",
                       tags: ["notes"],
                       ocrSnippets: ["Apple HIG — Sidebars", "Use clear hierarchy"],
                       isFavorite: false, isOCRComplete: true, thumbnailKind: .notes),
            Screenshot(id: UUID(), name: "Q2 forecast table.png",
                       createdAt: ago(7200),
                       pixelWidth: 2560, pixelHeight: 1440, byteSize: 820_000, format: "PNG",
                       tags: ["table", "finance"],
                       ocrSnippets: ["Q2 Forecast", "Revenue: $1.2M", "Spend: $620k"],
                       isFavorite: false, isOCRComplete: true, thumbnailKind: .table),
            Screenshot(id: UUID(), name: "RFC — quick-edit dialog.png",
                       createdAt: ago(9000),
                       pixelWidth: 2880, pixelHeight: 1800, byteSize: 1_320_000, format: "PNG",
                       tags: ["rfc", "design"],
                       ocrSnippets: ["RFC: Quick Edit Dialog", "Affordances", "Open questions"],
                       isFavorite: false, isOCRComplete: true, thumbnailKind: .document),
            Screenshot(id: UUID(), name: "Bench protocol.png",
                       createdAt: ago(11000),
                       pixelWidth: 2200, pixelHeight: 1500, byteSize: 580_000, format: "PNG",
                       tags: ["chemistry", "protocol"],
                       ocrSnippets: ["Reflux for 2h, monitor by TLC"],
                       isFavorite: false, isOCRComplete: false, thumbnailKind: .lectureSlide),
            Screenshot(id: UUID(), name: "Snippet — drag controller.png",
                       createdAt: ago(14400),
                       pixelWidth: 2560, pixelHeight: 1600, byteSize: 740_000, format: "PNG",
                       tags: ["code"],
                       ocrSnippets: ["class DragController", "func beginDrag(at:)"],
                       isFavorite: false, isOCRComplete: true, thumbnailKind: .code),
        ]
    }()
}
