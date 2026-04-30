import Foundation

/// Undo/redo stack for user operations.
@MainActor
final class OperationHistoryService {
    struct UndoAction {
        let title: String
        let undo: () -> Void
    }

    private var undoStack: [UndoAction] = []

    init() {}

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var nextUndoTitle: String {
        undoStack.last.map { "Undo \($0.title)" } ?? "Undo"
    }

    func push(title: String, undo: @escaping () -> Void) {
        undoStack.append(UndoAction(title: title, undo: undo))
    }

    func undoLast() {
        guard let action = undoStack.popLast() else { return }
        action.undo()
    }
}
