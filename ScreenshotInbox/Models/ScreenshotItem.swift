import Foundation

struct ScreenshotItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let createdAt: Date
    var isNew: Bool
    var isDismissed: Bool
    /// Set once the Phase 6 import finishes successfully; links this floating-inbox
    /// item to the canonical `Screenshot` row in the SQLite library.
    /// `nil` while import is in progress, if import failed, or for duplicates.
    var canonicalScreenshotID: UUID?

    init(
        id: UUID = UUID(),
        url: URL,
        createdAt: Date,
        isNew: Bool = true,
        isDismissed: Bool = false,
        canonicalScreenshotID: UUID? = nil
    ) {
        self.id = id
        self.url = url.standardizedFileURL
        self.createdAt = createdAt
        self.isNew = isNew
        self.isDismissed = isDismissed
        self.canonicalScreenshotID = canonicalScreenshotID
    }
}

