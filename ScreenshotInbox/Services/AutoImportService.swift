import Foundation

struct AutoImportResult {
    let source: ImportSource
    let importResult: ImportResult
}

@MainActor
final class AutoImportService {
    private let importService: ImportService
    private let importSourceRepository: ImportSourceRepository
    private let fileWatcher: FileWatcherService
    private let libraryRootURL: URL
    private let fileManager: FileManager
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    private var onResult: (@MainActor (AutoImportResult) -> Void)?

    init(
        importService: ImportService,
        importSourceRepository: ImportSourceRepository,
        fileWatcher: FileWatcherService,
        libraryRootURL: URL,
        fileManager: FileManager = .default
    ) {
        self.importService = importService
        self.importSourceRepository = importSourceRepository
        self.fileWatcher = fileWatcher
        self.libraryRootURL = libraryRootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    init() {
        self.importService = ImportService()
        self.importSourceRepository = ImportSourceRepository()
        self.fileWatcher = NullFileWatcherService()
        self.libraryRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileManager = .default
    }

    func start(onResult: @escaping @MainActor (AutoImportResult) -> Void) {
        self.onResult = onResult
        reloadWatchers()
    }

    func reloadWatchers() {
        do {
            let sources = try importSourceRepository.fetchEnabled()
                .filter { !isLibraryOrInsideLibrary(URL(fileURLWithPath: $0.folderPath, isDirectory: true)) }
            debugLog("loaded sources: \(sources.map(\.folderPath))")
            fileWatcher.replaceWatchedSources(sources) { [weak self] source, urls in
                Task { @MainActor in
                    self?.handleDetectedURLs(urls, from: source)
                }
            }
            debugLog("watching \(sources.count) source(s)")
        } catch {
            print("[AutoImport] reload failed: \(error)")
            fileWatcher.stopAll()
        }
    }

    func stop() {
        for task in pendingTasks.values { task.cancel() }
        pendingTasks.removeAll()
        fileWatcher.stopAll()
    }

    func scanEnabledSources() {
        do {
            for source in try importSourceRepository.fetchEnabled() {
                let folder = URL(fileURLWithPath: source.folderPath, isDirectory: true)
                guard !isLibraryOrInsideLibrary(folder) else { continue }
                handleDetectedURLs(candidateURLs(in: folder), from: source, requireEnabledSince: false)
            }
        } catch {
            print("[AutoImport] scan failed: \(error)")
        }
    }

    private func handleDetectedURLs(
        _ urls: [URL],
        from source: ImportSource,
        requireEnabledSince: Bool = true
    ) {
        let filtered = urls.filter { isAutoImportCandidate($0, source: source, requireEnabledSince: requireEnabledSince, shouldLog: true) }
        guard !filtered.isEmpty else { return }
        for url in filtered {
            let key = url.standardizedFileURL.path
            debugLog("detected file: \(key)")
            pendingTasks[key]?.cancel()
            pendingTasks[key] = Task { [weak self] in
                await self?.debounceAndImport(url: url, source: source)
            }
        }
    }

    private func debounceAndImport(url: URL, source: ImportSource) async {
        let key = url.standardizedFileURL.path
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !Task.isCancelled else { return }
        guard let firstSize = fileSize(url) else {
            pendingTasks.removeValue(forKey: key)
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        guard fileSize(url) == firstSize else {
            pendingTasks.removeValue(forKey: key)
            handleDetectedURLs([url], from: source)
            return
        }

        debugLog("importing file: \(url.path)")
        let result = await importService.importURLs([url])
        do {
            try importSourceRepository.updateLastScanned(uuid: source.uuid, date: Date())
        } catch {
            print("[AutoImport] last_scanned update failed: \(error)")
        }
        pendingTasks.removeValue(forKey: key)
        if result.imported.isEmpty && result.duplicates > 0 && result.failures.isEmpty {
            debugLog("skipped duplicate: \(url.lastPathComponent)")
        }
        debugLog("imported count: \(result.imported.count)")
        if let onResult {
            await MainActor.run {
                onResult(AutoImportResult(source: source, importResult: result))
            }
        }
    }

    private func isAutoImportCandidate(
        _ url: URL,
        source: ImportSource,
        requireEnabledSince: Bool,
        shouldLog: Bool = false
    ) -> Bool {
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent
        guard !name.hasPrefix(".") else {
            if shouldLog { debugLog("ignored unsupported file: \(standardized.path)") }
            return false
        }
        guard !name.hasSuffix(".tmp"), !name.hasSuffix(".download") else {
            if shouldLog { debugLog("ignored unsupported file: \(standardized.path)") }
            return false
        }
        guard AutoImportService.isSupportedImageURL(standardized) else {
            if shouldLog { debugLog("ignored unsupported file: \(standardized.path)") }
            return false
        }
        guard !isLibraryOrInsideLibrary(standardized) else {
            if shouldLog { debugLog("ignored library file: \(standardized.path)") }
            return false
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        guard !requireEnabledSince || isNewEnough(standardized, source: source) else { return false }
        return true
    }

    private func isNewEnough(_ url: URL, source: ImportSource) -> Bool {
        guard let enabledSince = source.enabledSince else { return true }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let date = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
        return date >= enabledSince.addingTimeInterval(-2)
    }

    private func isLibraryOrInsideLibrary(_ url: URL) -> Bool {
        let root = libraryRootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private func candidateURLs(in folder: URL) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            #if DEBUG
            print("[AutoImport] cannot scan folder: \(folder.path)")
            #endif
            return []
        }
        return urls
    }

    private func fileSize(_ url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return values.fileSize
    }

    static func isSupportedImageURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "tiff", "tif":
            return true
        default:
            return false
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AutoImport] \(message)")
        #endif
    }
}

private final class NullFileWatcherService: FileWatcherService {
    func replaceWatchedSources(
        _ sources: [ImportSource],
        onEvent: @escaping (ImportSource, [URL]) -> Void
    ) {}

    func stopAll() {}
}
