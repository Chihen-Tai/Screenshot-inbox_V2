import AppKit
import Quartz

/// Bridges Quick Look (`QLPreviewPanel`) into the app for spacebar preview.
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var items: [QuickLookPreviewItem] = []

    private override init() {}

    @MainActor
    func open(urls: [URL]) {
        items = Self.previewItems(for: urls)
        print("[QuickLook] opening \(items.count) item(s)")
        guard !items.isEmpty else { return }
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func close() {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else {
            items.removeAll()
            return
        }
        panel.orderOut(nil)
        items.removeAll()
        print("[QuickLook] closed")
    }

    static func previewItems(for urls: [URL], fileManager: FileManager = .default) -> [QuickLookPreviewItem] {
        urls.compactMap { url -> QuickLookPreviewItem? in
            let standardized = url.standardizedFileURL
            guard fileManager.fileExists(atPath: standardized.path) else {
                print("[MissingFile] file missing url = \(standardized.path)")
                return nil
            }
            return QuickLookPreviewItem(url: standardized)
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }
}

final class QuickLookPreviewItem: NSObject, QLPreviewItem {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    var previewItemURL: URL? {
        url
    }

    var previewItemTitle: String? {
        url.lastPathComponent
    }
}
