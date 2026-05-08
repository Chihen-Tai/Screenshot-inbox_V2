import Foundation
import Testing

struct CoreArchitectureTests {
    @Test
    func architectureCheckScriptExists() {
        let script = repositoryRoot()
            .appendingPathComponent("scripts/check-architecture.sh")
        #expect(FileManager.default.fileExists(atPath: script.path))
    }

    @Test
    func coreAndModelsDoNotImportUIFrameworks() throws {
        let root = repositoryRoot()
        let checkedRoots = [
            root.appendingPathComponent("ScreenshotInbox/Core", isDirectory: true),
            root.appendingPathComponent("ScreenshotInbox/Models", isDirectory: true),
        ]
        let bannedImports = ["SwiftUI", "AppKit", "Cocoa", "Vision", "QuickLook"]
        let bannedTokens = ["NSImage", "NSView", "NSWorkspace", "NSPasteboard", "SwiftUI.Image"]
        var violations: [String] = []

        for directory in checkedRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let text = try String(contentsOf: fileURL)
                let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                for framework in bannedImports where text.contains("import \(framework)") {
                    violations.append("\(relativePath): imports \(framework)")
                }
                for token in bannedTokens where text.contains(token) {
                    violations.append("\(relativePath): references \(token)")
                }
            }
        }

        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return url
    }
}
