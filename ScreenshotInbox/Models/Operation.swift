import Foundation

/// Undoable operation record (move, trash, restore, tag).
/// Named `AppOperation` to avoid shadowing `Foundation.Operation`.
struct AppOperation: Identifiable, Hashable {
    let id: UUID
    var kind: String
    var performedAt: Date
    // TODO: typed payload for inverse application.
}
