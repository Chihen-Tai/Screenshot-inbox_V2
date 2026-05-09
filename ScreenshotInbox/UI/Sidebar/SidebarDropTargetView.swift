import AppKit
import SwiftUI

struct SidebarDropTargetView: NSViewRepresentable {
    let targetName: String
    var targetCollectionUUID: String? = nil
    let onTargeted: (Bool) -> Void
    let onDrop: ([UUID]) -> Void
    var onCollectionHover: ((String, SidebarCollectionDropPosition) -> Void)? = nil
    var onCollectionDrop: ((String, SidebarCollectionDropPosition) -> Void)? = nil

    func makeNSView(context: Context) -> DropTargetNSView {
        let view = DropTargetNSView()
        view.targetName = targetName
        view.targetCollectionUUID = targetCollectionUUID
        view.onTargeted = onTargeted
        view.onDrop = onDrop
        view.onCollectionHover = onCollectionHover
        view.onCollectionDrop = onCollectionDrop
        return view
    }

    func updateNSView(_ nsView: DropTargetNSView, context: Context) {
        nsView.targetName = targetName
        nsView.targetCollectionUUID = targetCollectionUUID
        nsView.onTargeted = onTargeted
        nsView.onDrop = onDrop
        nsView.onCollectionHover = onCollectionHover
        nsView.onCollectionDrop = onCollectionDrop
    }
}

enum SidebarCollectionDropPosition {
    case before
    case after
}

final class DropTargetNSView: NSView {
    var targetName: String = ""
    var targetCollectionUUID: String?
    var onTargeted: ((Bool) -> Void)?
    var onDrop: (([UUID]) -> Void)?
    var onCollectionHover: ((String, SidebarCollectionDropPosition) -> Void)?
    var onCollectionDrop: ((String, SidebarCollectionDropPosition) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        registerForDraggedTypes([
            InternalScreenshotDrag.pasteboardType,
            InternalCollectionDrag.pasteboardType
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsInternalScreenshotIDs(sender) || acceptsInternalCollectionID(sender) else { return [] }
        onTargeted?(true)
        return acceptsInternalCollectionID(sender) ? .move : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let collectionUUID = acceptedCollectionID(sender) {
            let position = collectionDropPosition(for: sender)
            onCollectionHover?(collectionUUID, position)
            return .move
        }
        guard acceptsInternalScreenshotIDs(sender) else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargeted?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargeted?(false) }
        if let collectionUUID = acceptedCollectionID(sender) {
            let position = collectionDropPosition(for: sender)
            onCollectionDrop?(collectionUUID, position)
            return true
        }
        let raw = sender.draggingPasteboard.string(forType: InternalScreenshotDrag.pasteboardType)
        let ids = InternalScreenshotDrag.decode(raw)
        guard !ids.isEmpty else { return false }
        onDrop?(ids)
        return true
    }

    private func acceptsInternalScreenshotIDs(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.availableType(from: [InternalScreenshotDrag.pasteboardType]) != nil
    }

    private func acceptsInternalCollectionID(_ sender: NSDraggingInfo) -> Bool {
        acceptedCollectionID(sender) != nil
    }

    private func acceptedCollectionID(_ sender: NSDraggingInfo) -> String? {
        guard targetCollectionUUID != nil,
              onCollectionDrop != nil else {
            return nil
        }
        let pasteboard = sender.draggingPasteboard
        if pasteboard.availableType(from: [InternalCollectionDrag.pasteboardType]) != nil {
            return InternalCollectionDrag.decode(from: pasteboard)
        }
        if let fallback = pasteboard.string(forType: .string),
           fallback.hasPrefix("collection:") {
            return InternalCollectionDrag.decode(fallback)
        }
        return nil
    }

    private func collectionDropPosition(for sender: NSDraggingInfo) -> SidebarCollectionDropPosition {
        let localPoint = convert(sender.draggingLocation, from: nil)
        return localPoint.y >= bounds.midY ? .before : .after
    }
}
