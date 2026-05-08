import Foundation

final class MacFileOpener: FileOpening {
    private let service: MacFileActionService

    init(service: MacFileActionService = MacFileActionService()) {
        self.service = service
    }

    func openFile(path: String) throws {
        try service.openFile(path: path)
    }

    func revealInFinder(path: String) throws {
        try service.revealInFinder(path: path)
    }

    @MainActor
    func openWith(path: String) throws {
        try service.openWith(path: path)
    }
}
