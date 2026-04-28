import AppKit
import Foundation

enum MacFileActionError: Error {
    case missingFile(URL)
    case openFailed(URL)
}

/// macOS-only file actions for managed originals.
final class MacFileActionService {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func open(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw MacFileActionError.missingFile(url)
        }
        guard workspace.open(url) else {
            throw MacFileActionError.openFailed(url)
        }
    }

    func revealInFinder(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw MacFileActionError.missingFile(url)
        }
        workspace.activateFileViewerSelecting([url])
    }
}
