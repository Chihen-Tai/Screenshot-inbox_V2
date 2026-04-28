import Foundation

protocol FileWatcherService: AnyObject {
    func replaceWatchedSources(
        _ sources: [ImportSource],
        onEvent: @escaping (ImportSource, [URL]) -> Void
    )
    func stopAll()
}
