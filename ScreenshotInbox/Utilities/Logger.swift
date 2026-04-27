import Foundation
import OSLog

enum Log {
    static let app = Logger(subsystem: "com.screenshotinbox.v2", category: "app")
    // TODO: dedicated categories for import, ocr, export, persistence.
}
