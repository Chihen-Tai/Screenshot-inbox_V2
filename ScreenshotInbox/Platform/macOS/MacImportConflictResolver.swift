import AppKit
import Foundation

struct MacImportConflictResolver: ImportConflictResolving {
    func resolve(conflicts: [ImportConflict]) async -> [ImportConflictDecision] {
        guard !conflicts.isEmpty else { return [] }
        let resolution = await MainActor.run {
            conflicts.count == 1
                ? resolveSingle(conflicts[0])
                : resolveBatch(count: conflicts.count)
        }
        return conflicts.map { ImportConflictDecision(conflict: $0, resolution: resolution) }
    }

    @MainActor
    private func resolveSingle(_ conflict: ImportConflict) -> ImportConflictResolution {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Duplicate Screenshot Found"
        alert.informativeText = """
        A screenshot with the same file already exists.

        Incoming: \(conflict.incomingFilename)
        Existing: \(conflict.existingFilename)
        """
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace Existing")
        alert.addButton(withTitle: "Skip")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .keepBoth
        case .alertSecondButtonReturn:
            return .replaceExisting
        default:
            return .skip
        }
    }

    @MainActor
    private func resolveBatch(count: Int) -> ImportConflictResolution {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Duplicate Screenshots Found"
        alert.informativeText = "\(count) imported file\(count == 1 ? "" : "s") already exist in Screenshot Inbox."
        alert.addButton(withTitle: "Keep Both for All")
        alert.addButton(withTitle: "Replace Existing for All")
        alert.addButton(withTitle: "Skip All")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .keepBoth
        case .alertSecondButtonReturn:
            return .replaceExisting
        default:
            return .skip
        }
    }
}
