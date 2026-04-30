import Foundation

struct SourceFolderSyncChanges {
    var renamed: [SourceFolderRenamedOriginal] = []
    var missing: [Screenshot] = []
}

struct SourceFolderRenamedOriginal: Hashable {
    let screenshot: Screenshot
    let oldOriginalURL: URL
    let newOriginalURL: URL
}

/// Validates source-folder paths recorded at import time. This service never
/// deletes managed library files; it only identifies app records whose external
/// source path is missing and safe to act on.
final class SourceFolderSyncService {
    private let libraryRootURL: URL
    private let fileManager: FileManager

    init(libraryRootURL: URL, fileManager: FileManager = .default) {
        self.libraryRootURL = libraryRootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func missingOriginalScreenshots(
        in screenshots: [Screenshot],
        scopedToSourceFolders sourceFolders: [URL]
    ) -> [Screenshot] {
        (try? reconcileOriginalSourceChanges(
            in: screenshots,
            scopedToSourceFolders: sourceFolders,
            detectRenamesByHash: false
        ).missing) ?? []
    }

    func reconcileOriginalSourceChanges(
        in screenshots: [Screenshot],
        scopedToSourceFolders sourceFolders: [URL],
        detectRenamesByHash: Bool
    ) throws -> SourceFolderSyncChanges {
        let scopes = sourceFolders
            .map { $0.standardizedFileURL }
            .filter { isReadableDirectory($0) && !isManagedLibraryURL($0) }

        guard !scopes.isEmpty else { return SourceFolderSyncChanges() }

        var changes = SourceFolderSyncChanges()
        for screenshot in screenshots {
            guard !screenshot.isTrashed,
                  let originalURL = originalURL(for: screenshot),
                  !isManagedLibraryURL(originalURL),
                  scopes.contains(where: { contains(originalURL, in: $0) }),
                  !fileManager.fileExists(atPath: originalURL.path) else {
                continue
            }
            if detectRenamesByHash,
               let renamedURL = try uniqueHashMatch(for: screenshot, oldOriginalURL: originalURL, scopes: scopes) {
                changes.renamed.append(SourceFolderRenamedOriginal(
                    screenshot: screenshot,
                    oldOriginalURL: originalURL,
                    newOriginalURL: renamedURL
                ))
            } else {
                changes.missing.append(screenshot)
            }
        }
        return changes
    }

    private func uniqueHashMatch(for screenshot: Screenshot, oldOriginalURL: URL, scopes: [URL]) throws -> URL? {
        guard let hash = screenshot.fileHash, !hash.isEmpty else { return nil }
        let folder = oldOriginalURL.deletingLastPathComponent().standardizedFileURL
        guard scopes.contains(where: { contains(folder, in: $0) || contains($0, in: folder) }),
              isReadableDirectory(folder) else {
            return nil
        }
        let candidates = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { candidate in
            candidate.standardizedFileURL != oldOriginalURL
                && isSupportedImageURL(candidate)
                && !isManagedLibraryURL(candidate)
        }

        var matches: [URL] = []
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            if (try? FileHash.sha256Hex(of: candidate)) == hash {
                matches.append(candidate.standardizedFileURL)
                if matches.count > 1 { return nil }
            }
        }
        return matches.first
    }

    private func isSupportedImageURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "tiff", "tif":
            return true
        default:
            return false
        }
    }

    private func originalURL(for screenshot: Screenshot) -> URL? {
        guard let path = screenshot.originalPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    private func contains(_ url: URL, in folder: URL) -> Bool {
        let folderPath = folder.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == folderPath || path.hasPrefix(folderPath + "/")
    }

    private func isManagedLibraryURL(_ url: URL) -> Bool {
        let root = libraryRootURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: url.path)
    }
}
