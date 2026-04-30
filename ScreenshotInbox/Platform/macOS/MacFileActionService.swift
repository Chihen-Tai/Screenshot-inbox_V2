import AppKit
import Foundation
import UniformTypeIdentifiers

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

    @MainActor
    func openWithPicker(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw MacFileActionError.missingFile(url)
        }

        let panel = NSOpenPanel()
        panel.title = "Open With"
        panel.message = "Choose an application to open \(url.lastPathComponent)."
        panel.prompt = "Open"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let appURL = panel.urls.first else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        workspace.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                #if DEBUG
                print("[FileAction] open with failed: \(error)")
                #endif
            }
        }
    }
}
