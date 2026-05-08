import AppKit
import Foundation

@MainActor
final class ScreenshotInboxStore: ObservableObject {
    enum ImportSource: String {
        case screenshotWatcher
        case autoImport
        case manualImport
        case dragDrop
    }

    enum ImportIgnoreReason: Equatable {
        case missingFile
        case unsupportedFileType
        case fileStillChanging
        case duplicate
    }

    struct ImportOutcome: Equatable {
        let item: ScreenshotItem?
        let ignoredReason: ImportIgnoreReason?

        var wasInserted: Bool { item != nil }

        static func inserted(_ item: ScreenshotItem) -> ImportOutcome {
            ImportOutcome(item: item, ignoredReason: nil)
        }

        static func ignored(_ reason: ImportIgnoreReason) -> ImportOutcome {
            ImportOutcome(item: nil, ignoredReason: reason)
        }
    }

    static let shared = ScreenshotInboxStore()

    // TODO: Persist Phase 1 inbox state to Application Support once the item
    // lifecycle settles. For now this is intentionally in-memory.
    @Published private(set) var items: [ScreenshotItem] = []

    private static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif"]

    private let fileManager: FileManager
    private var knownFileURLs: Set<URL> = []
    private var knownResourceIdentifiers: Set<String> = []
    private var knownFingerprints: Set<FileFingerprint> = []
    private var identityByItemID: [UUID: StoredIdentity] = [:]
    private var latestScreenshotID: UUID?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var allItems: [ScreenshotItem] {
        items
    }

    var newItems: [ScreenshotItem] {
        items.filter { $0.isNew && !$0.isDismissed }
    }

    var newUndismissedCount: Int {
        newItems.count
    }

    var dismissedItems: [ScreenshotItem] {
        items.filter(\.isDismissed)
    }

    var latestItem: ScreenshotItem? {
        items.first
    }

    var latestUndismissedItem: ScreenshotItem? {
        items.first { !$0.isDismissed }
    }

    var latestScreenshot: ScreenshotItem? {
        latestUndismissedItem
    }

    func registerExistingLibraryOriginalURLs(_ urls: [URL]) {
        for url in urls {
            let standardizedURL = normalizedFileURL(url)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            knownFileURLs.insert(standardizedURL)
            if let resourceIdentifier = fileResourceIdentifier(for: standardizedURL) {
                knownResourceIdentifiers.insert(resourceIdentifier)
            }
            if let fingerprint = fileFingerprint(for: standardizedURL) {
                knownFingerprints.insert(fingerprint)
            }
        }
    }

    @discardableResult
    func addScreenshot(at url: URL, createdAt: Date = Date()) -> ScreenshotItem? {
        let standardizedURL = normalizedFileURL(url)
        guard !isKnown(url: standardizedURL, resourceIdentifier: nil, fingerprint: nil) else {
            print("[Import] duplicate ignored url = \(standardizedURL.path)")
            return nil
        }

        return insertScreenshot(
            url: standardizedURL,
            createdAt: createdAt,
            resourceIdentifier: nil,
            fingerprint: nil
        )
    }

    @discardableResult
    func importScreenshotIfNeeded(url: URL, source: ImportSource) -> ImportOutcome {
        let standardizedURL = normalizedFileURL(url)
        print("[Import] source = \(source.rawValue) url = \(standardizedURL.path)")

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            print("[Import] ignored missing url = \(standardizedURL.path)")
            logCurrentItemCount()
            return .ignored(.missingFile)
        }

        guard Self.supportedExtensions.contains(standardizedURL.pathExtension.lowercased()) else {
            print("[Import] ignored unsupported url = \(standardizedURL.path)")
            logCurrentItemCount()
            return .ignored(.unsupportedFileType)
        }

        guard var fingerprint = fileFingerprint(for: standardizedURL),
              fingerprint.fileSize > 0,
              fingerprint.isRegularFile else {
            print("[Import] ignored unsupported url = \(standardizedURL.path)")
            logCurrentItemCount()
            return .ignored(.unsupportedFileType)
        }

        guard let stableFingerprint = waitForStableFingerprint(at: standardizedURL, initial: fingerprint) else {
            print("[Import] ignored unstable url = \(standardizedURL.path)")
            logCurrentItemCount()
            return .ignored(.fileStillChanging)
        }
        fingerprint = stableFingerprint

        let resourceIdentifier = fileResourceIdentifier(for: standardizedURL)
        guard !isKnown(
            url: standardizedURL,
            resourceIdentifier: resourceIdentifier,
            fingerprint: fingerprint
        ) else {
            print("[Import] duplicate ignored url = \(standardizedURL.path)")
            logCurrentItemCount()
            return .ignored(.duplicate)
        }

        let item = insertScreenshot(
            url: standardizedURL,
            createdAt: fingerprint.creationDate ?? Date(),
            resourceIdentifier: resourceIdentifier,
            fingerprint: fingerprint
        )
        print("[Import] inserted item id = \(item.id)")
        logCurrentItemCount()
        logCount()
        return .inserted(item)
    }

    func dismissLatestScreenshot() {
        guard let item = latestUndismissedItem else { return }
        dismiss(item)
    }

    func dismiss(_ item: ScreenshotItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let filename = items[index].url.lastPathComponent
        print("[Dismiss] dismiss called for item: \(filename)")
        // Copy-then-reassign: in-place subscript element mutations on a @Published
        // array go through the array's _modify accessor and bypass willSet, so
        // $items never publishes and MenuBarController never refreshes the badge.
        // Assigning a whole new array guarantees the @Published setter fires.
        var updated = items
        updated[index].isNew = false
        updated[index].isDismissed = true
        items = updated
        if latestScreenshotID == item.id {
            latestScreenshotID = latestUndismissedItem?.id
        }
        print("[Dismiss] item dismissed id = \(item.id)")
        print("[Dismiss] isNew false, isDismissed true for \(filename)")
        logCount()
    }

    func dismissCanonicalItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var updated = items
        var dismissed = 0
        for index in updated.indices where updated[index].canonicalScreenshotID.map(ids.contains) == true {
            guard updated[index].isNew || !updated[index].isDismissed else { continue }
            updated[index].isNew = false
            updated[index].isDismissed = true
            dismissed += 1
            print("[Dismiss] item dismissed id = \(updated[index].id)")
        }
        guard dismissed > 0 else { return }
        items = updated
        print("[Dismiss] canonical dismiss count = \(dismissed)")
        logCount()
    }

    /// Called by the import pipeline once the Phase 6 SQLite import succeeds.
    /// Links the floating-inbox item (identified by source URL) to the canonical
    /// `Screenshot` row so callers can navigate to it in the main inbox.
    func updateCanonicalID(for url: URL, id: UUID) {
        let standardized = normalizedFileURL(url)
        guard let index = items.firstIndex(where: { $0.url == standardized }) else { return }
        items[index].canonicalScreenshotID = id
        print("[ScreenshotInboxStore] linked url=\(standardized.lastPathComponent) to canonical id=\(id)")
    }

    /// Removes a floating-inbox item by source URL. Called when Phase 6 import
    /// fails so a stale item is not left in the panel.
    func remove(at url: URL) {
        let standardized = normalizedFileURL(url)
        let removedIDs = items.filter { $0.url == standardized }.map(\.id)
        items = items.filter { $0.url != standardized }
        for id in removedIDs {
            unregisterIdentity(for: id)
        }
        if let latest = latestScreenshotID, !items.contains(where: { $0.id == latest }) {
            latestScreenshotID = latestUndismissedItem?.id
        }
        print("[ScreenshotInboxStore] removed failed-import item: \(standardized.lastPathComponent)")
        logCurrentItemCount()
        logCount()
    }

    func clearDismissed() {
        let dismissedIDs = dismissedItems.map(\.id)
        guard !dismissedIDs.isEmpty else { return }
        items = items.filter { !$0.isDismissed }
        for id in dismissedIDs {
            unregisterIdentity(for: id)
        }
        logCurrentItemCount()
        logCount()
    }

    func copy(_ item: ScreenshotItem, to pasteboard: NSPasteboard = .general) {
        guard fileManager.fileExists(atPath: item.url.path) else {
            print("[MissingFile] file missing url = \(item.url.path)")
            return
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])

        if let image = NSImage(contentsOf: item.url),
           let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }
        print("[Copy] copied 1 item(s)")
        print("[ScreenshotInboxStore] copied: \(item.url.path)")
    }

    func reveal(_ item: ScreenshotItem) {
        guard fileManager.fileExists(atPath: item.url.path) else {
            print("[MissingFile] file missing url = \(item.url.path)")
            return
        }
        print("[Reveal] revealing 1 item(s)")
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ScreenshotItem) {
        guard fileManager.fileExists(atPath: item.url.path) else {
            print("[MissingFile] file missing url = \(item.url.path)")
            return
        }
        NSWorkspace.shared.open(item.url)
    }

    func deleteFileWithConfirmation(_ item: ScreenshotItem) {
        let alert = NSAlert()
        alert.messageText = "Move 1 screenshot to Trash?"
        alert.informativeText = "The file will be moved to Trash. This cannot be undone from Screenshot Inbox."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        print("[Trash] confirmation shown for 1 item(s)")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            remove(item)
            print("[Trash] moved to trash 1 item(s)")
            print("[ScreenshotInboxStore] file moved to Trash: \(item.url.path)")
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.messageText = "Could not delete screenshot"
            errorAlert.runModal()
        }
    }

    private func remove(_ item: ScreenshotItem) {
        items = items.filter { $0.id != item.id }
        unregisterIdentity(for: item.id)
        if latestScreenshotID == item.id {
            latestScreenshotID = latestUndismissedItem?.id
        }
        logCurrentItemCount()
        logCount()
    }

    private func insertScreenshot(
        url: URL,
        createdAt: Date,
        resourceIdentifier: String?,
        fingerprint: FileFingerprint?
    ) -> ScreenshotItem {
        let item = ScreenshotItem(url: url, createdAt: createdAt)
        items.insert(item, at: 0)
        latestScreenshotID = item.id
        registerIdentity(
            StoredIdentity(
                url: url,
                resourceIdentifier: resourceIdentifier,
                fingerprint: fingerprint
            ),
            for: item.id
        )
        return item
    }

    private func registerIdentity(_ identity: StoredIdentity, for id: UUID) {
        knownFileURLs.insert(identity.url)
        if let resourceIdentifier = identity.resourceIdentifier {
            knownResourceIdentifiers.insert(resourceIdentifier)
        }
        if let fingerprint = identity.fingerprint {
            knownFingerprints.insert(fingerprint)
        }
        identityByItemID[id] = identity
    }

    private func unregisterIdentity(for id: UUID) {
        guard let identity = identityByItemID.removeValue(forKey: id) else { return }
        knownFileURLs.remove(identity.url)
        if let resourceIdentifier = identity.resourceIdentifier {
            knownResourceIdentifiers.remove(resourceIdentifier)
        }
        if let fingerprint = identity.fingerprint {
            knownFingerprints.remove(fingerprint)
        }
    }

    private func isKnown(
        url: URL,
        resourceIdentifier: String?,
        fingerprint: FileFingerprint?
    ) -> Bool {
        if knownFileURLs.contains(url) { return true }
        if let resourceIdentifier, knownResourceIdentifiers.contains(resourceIdentifier) { return true }
        if let fingerprint, knownFingerprints.contains(fingerprint) { return true }
        return false
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func waitForStableFingerprint(at url: URL, initial: FileFingerprint) -> FileFingerprint? {
        var previous = initial
        for _ in 0..<4 {
            Thread.sleep(forTimeInterval: 0.15)
            guard let current = fileFingerprint(for: url) else { return nil }
            if current.fileSize == previous.fileSize,
               current.modificationTime == previous.modificationTime {
                return current
            }
            previous = current
        }
        return nil
    }

    private func fileResourceIdentifier(for url: URL) -> String? {
        guard let value = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
            .fileResourceIdentifier else {
            return nil
        }
        return String(describing: value)
    }

    private func fileFingerprint(for url: URL) -> FileFingerprint? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]) else {
            return nil
        }
        return FileFingerprint(
            filename: url.lastPathComponent,
            creationTime: values.creationDate?.timeIntervalSinceReferenceDate,
            fileSize: values.fileSize ?? 0,
            modificationTime: values.contentModificationDate?.timeIntervalSinceReferenceDate,
            isRegularFile: values.isRegularFile == true
        )
    }

    private func logCurrentItemCount() {
        print("[Import] current item count = \(items.count)")
    }

    private func logCount() {
        print("[Count] newUndismissedCount = \(newUndismissedCount)")
    }
}

private struct StoredIdentity {
    let url: URL
    let resourceIdentifier: String?
    let fingerprint: FileFingerprint?
}

private struct FileFingerprint: Hashable {
    let filename: String
    let creationTime: TimeInterval?
    let fileSize: Int
    let modificationTime: TimeInterval?
    let isRegularFile: Bool

    var creationDate: Date? {
        creationTime.map { Date(timeIntervalSinceReferenceDate: $0) }
    }
}
