import AppKit
import Foundation

enum DragPasteboardTypes {
    static let collectionIDString = "com.screenshotinbox.collection-id"
    static let screenshotIDsString = "com.screenshotinbox.screenshot-ids"

    static let collectionID = NSPasteboard.PasteboardType(collectionIDString)
    static let screenshotIDs = NSPasteboard.PasteboardType(screenshotIDsString)
}
