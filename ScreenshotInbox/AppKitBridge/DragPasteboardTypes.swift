import AppKit
import Foundation

enum DragPasteboardTypes {
    static let collectionIDString = "com.screenshotinbox.collection-id"
    static let screenshotIDsString = "com.screenshotinbox.screenshot-ids"
    static let clipboardOperationString = "com.screenshotinbox.clipboard-operation"
    static let sourceSidebarDestinationString = "com.screenshotinbox.source-sidebar-destination"
    static let sourceCollectionIDString = "com.screenshotinbox.source-collection-id"

    static let collectionID = NSPasteboard.PasteboardType(collectionIDString)
    static let screenshotIDs = NSPasteboard.PasteboardType(screenshotIDsString)
    static let clipboardOperation = NSPasteboard.PasteboardType(clipboardOperationString)
    static let sourceSidebarDestination = NSPasteboard.PasteboardType(sourceSidebarDestinationString)
    static let sourceCollectionID = NSPasteboard.PasteboardType(sourceCollectionIDString)
}
