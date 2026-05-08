import AppKit
import Foundation

final class MacShareService: SharingProviding {
    @discardableResult
    func shareFiles(paths: [String]) -> Int {
        let urls = paths.map(URL.init(fileURLWithPath:))
        guard !urls.isEmpty else { return 0 }
        let picker = NSSharingServicePicker(items: urls)
        if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
        return urls.count
    }
}
