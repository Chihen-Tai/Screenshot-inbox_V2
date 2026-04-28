import AppKit
import SwiftUI

struct SidebarDropTargetView: NSViewRepresentable {
    let targetName: String
    let onTargeted: (Bool) -> Void
    let onDrop: ([UUID]) -> Void

    func makeNSView(context: Context) -> DropTargetNSView {
        let view = DropTargetNSView()
        view.targetName = targetName
        view.onTargeted = onTargeted
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DropTargetNSView, context: Context) {
        nsView.targetName = targetName
        nsView.onTargeted = onTargeted
        nsView.onDrop = onDrop
    }
}

final class DropTargetNSView: NSView {
    var targetName: String = ""
    var onTargeted: ((Bool) -> Void)?
    var onDrop: (([UUID]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        registerForDraggedTypes([InternalScreenshotDrag.pasteboardType])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        print("[SidebarDrop] entered target: \(targetName)")
        print("[SidebarDrop] validate target: \(targetName) pasteboardTypes=\(sender.draggingPasteboard.types?.map(\.rawValue) ?? [])")
        guard hasInternalScreenshotIDs(sender) else { return [] }
        onTargeted?(true)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasInternalScreenshotIDs(sender) else { return [] }
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargeted?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        print("[SidebarDrop] perform drop target: \(targetName)")
        defer { onTargeted?(false) }
        let raw = sender.draggingPasteboard.string(forType: InternalScreenshotDrag.pasteboardType)
        let ids = InternalScreenshotDrag.decode(raw)
        print("[SidebarDrop] decoded IDs: \(ids.map(\.uuidString))")
        guard !ids.isEmpty else { return false }
        onDrop?(ids)
        return true
    }

    private func hasInternalScreenshotIDs(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.availableType(from: [InternalScreenshotDrag.pasteboardType]) != nil
    }
}
