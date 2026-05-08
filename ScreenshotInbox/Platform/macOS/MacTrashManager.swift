import Foundation

final class MacTrashManager: FileTrashManaging {
    private let service: MacFileActionService

    init(service: MacFileActionService = MacFileActionService()) {
        self.service = service
    }

    func moveToSystemTrash(path: String) throws {
        try service.moveToSystemTrash(path: path)
    }
}
