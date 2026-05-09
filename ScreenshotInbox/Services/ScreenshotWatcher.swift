import Darwin
import Foundation

final class ScreenshotWatcher {
    typealias Handler = @MainActor (URL) -> Void

    private static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    private let folderURL: URL
    let watchedFolderURL: URL
    private let presentationDelay: TimeInterval
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.screenshotinbox.phase0-watcher", qos: .utility)
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var knownFileURLs: Set<URL> = []
    private var pendingFileURLs: Set<URL> = []
    private var watchStartedAt: Date?
    /// Fires on the main actor for every kqueue folder event (writes, renames,
    /// deletions). Used by AppState to schedule live source-folder validation so
    /// inbox items whose originals were deleted/renamed are detected promptly.
    private let onFolderEvent: (@MainActor () -> Void)?
    private let onScreenshotDetected: Handler

    init(
        folderURL: URL = ScreenshotWatcher.defaultScreenshotFolderURL(),
        presentationDelay: TimeInterval = 2.0,
        fileManager: FileManager = .default,
        onFolderEvent: (@MainActor () -> Void)? = nil,
        onScreenshotDetected: @escaping Handler
    ) {
        self.folderURL = folderURL.standardizedFileURL
        self.watchedFolderURL = folderURL.standardizedFileURL
        self.presentationDelay = presentationDelay
        self.fileManager = fileManager
        self.onFolderEvent = onFolderEvent
        self.onScreenshotDetected = onScreenshotDetected
    }

    deinit {
        stop()
    }

    func start() {
        guard source == nil else { return }
        watchStartedAt = Date()

        fd = open(folderURL.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[ScreenshotWatcher] failed to start path=\(folderURL.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if let folderEvent = self.onFolderEvent {
                Task { @MainActor in folderEvent() }
            }
            self.scanForNewScreenshots()
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fd = -1
        watchStartedAt = nil
    }

    static func defaultScreenshotFolderURL(fileManager: FileManager = .default) -> URL {
        if let configuredLocation = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"),
           !configuredLocation.isEmpty {
            let expanded = (configuredLocation as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }

        return fileManager.urls(for: .desktopDirectory, in: .userDomainMask)
            .first?
            .standardizedFileURL ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    static func isCandidateScreenshotFile(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let filename = standardizedURL.lastPathComponent
        guard !filename.isEmpty, !filename.hasPrefix(".") else { return false }
        guard supportedExtensions.contains(standardizedURL.pathExtension.lowercased()) else { return false }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        guard let values = try? standardizedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) > 0 else {
            return false
        }
        return true
    }

    private func scanForNewScreenshots() {
        for url in candidateURLs() where !knownFileURLs.contains(url) && !pendingFileURLs.contains(url) {
            pendingFileURLs.insert(url)
            waitForFileThenPublish(url)
        }
    }

    private func candidateURLs() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .map(\.standardizedFileURL)
            .filter { Self.isCandidateScreenshotFile($0, fileManager: fileManager) }
            .filter { isNewSinceWatcherStarted($0) }
    }

    private func waitForFileThenPublish(_ url: URL) {
        queue.asyncAfter(deadline: .now() + presentationDelay) { [weak self] in
            guard let self else { return }
            guard Self.isCandidateScreenshotFile(url, fileManager: self.fileManager),
                  self.fileSize(at: url) == self.fileSizeAfterBriefPause(at: url) else {
                self.pendingFileURLs.remove(url)
                return
            }

            self.knownFileURLs.insert(url)
            self.pendingFileURLs.remove(url)
            Task { @MainActor [onScreenshotDetected] in
                onScreenshotDetected(url)
            }
        }
    }

    private func fileSizeAfterBriefPause(at url: URL) -> Int? {
        Thread.sleep(forTimeInterval: 0.2)
        return fileSize(at: url)
    }

    private func fileSize(at url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    private func isNewSinceWatcherStarted(_ url: URL) -> Bool {
        guard let watchStartedAt else { return true }
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
            return false
        }
        let fileDate = values.creationDate ?? values.contentModificationDate ?? .distantPast
        return fileDate >= watchStartedAt.addingTimeInterval(-1)
    }
}
