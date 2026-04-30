import Foundation

struct FolderAccess: Hashable {
    let url: URL
    let isSecurityScoped: Bool
    let bookmarkData: Data?
}

/// Release-readiness boundary for future sandboxing.
///
/// Current GitHub builds are non-sandboxed, so this service normalizes folder
/// URLs and leaves security-scoped bookmark data empty. When sandboxing is
/// enabled later, callers can keep using this boundary while the
/// implementation starts resolving and storing bookmarks.
final class FolderAccessService {
    static let isSandboxEnabled = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    func resolveAccess(for folderURL: URL) -> FolderAccess {
        FolderAccess(
            url: folderURL.standardizedFileURL,
            isSecurityScoped: Self.isSandboxEnabled,
            bookmarkData: nil
        )
    }

    func validateReadableFolder(_ folderURL: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: folderURL.path)
    }

    func accessFailureMessage(for folderURL: URL) -> String {
        "Screenshot Inbox cannot access this folder. Please choose it again in Settings."
    }
}
