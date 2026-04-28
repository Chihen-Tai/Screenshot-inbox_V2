import Foundation
import Darwin

final class MacFileWatcherService: FileWatcherService {
    private var watchers: [String: DirectoryWatcher] = [:]
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func replaceWatchedSources(
        _ sources: [ImportSource],
        onEvent: @escaping (ImportSource, [URL]) -> Void
    ) {
        let uniqueSources = Dictionary(grouping: sources, by: { $0.folderPath })
            .compactMap { $0.value.first }
        let desiredPaths = Set(uniqueSources.map(\.folderPath))

        for path in watchers.keys where !desiredPaths.contains(path) {
            watchers[path]?.stop()
            watchers.removeValue(forKey: path)
        }

        for source in uniqueSources {
            guard watchers[source.folderPath] == nil else { continue }
            let folderURL = URL(fileURLWithPath: source.folderPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                print("[FileWatcher] missing folder: \(folderURL.path)")
                continue
            }
            do {
                let fileManager = self.fileManager
                let watcher = try DirectoryWatcher(source: source, folderURL: folderURL) { changedSource, folder in
                    let urls = (try? fileManager.contentsOfDirectory(
                        at: folder,
                        includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []
                    onEvent(changedSource, urls)
                }
                watchers[source.folderPath] = watcher
                watcher.start()
                print("[FileWatcher] watching \(folderURL.path)")
            } catch {
                print("[FileWatcher] could not watch \(folderURL.path): \(error)")
            }
        }
    }

    func stopAll() {
        for watcher in watchers.values { watcher.stop() }
        watchers.removeAll()
    }
}

private final class DirectoryWatcher {
    private let source: ImportSource
    private let folderURL: URL
    private let callback: (ImportSource, URL) -> Void
    private let fd: Int32
    private let dispatchSource: DispatchSourceFileSystemObject

    init(
        source: ImportSource,
        folderURL: URL,
        callback: @escaping (ImportSource, URL) -> Void
    ) throws {
        self.source = source
        self.folderURL = folderURL
        self.callback = callback
        let fd = open(folderURL.path, O_EVTONLY)
        guard fd >= 0 else {
            throw CocoaError(.fileReadNoPermission)
        }
        self.fd = fd
        self.dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        self.dispatchSource.setEventHandler { [source, folderURL, callback] in
            callback(source, folderURL)
        }
        self.dispatchSource.setCancelHandler { [fd] in
            close(fd)
        }
    }

    func start() {
        dispatchSource.resume()
    }

    func stop() {
        dispatchSource.cancel()
    }
}
