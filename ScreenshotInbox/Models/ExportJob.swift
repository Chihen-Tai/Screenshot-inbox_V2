import Foundation

struct ExportJob: Identifiable, Hashable {
    let id: UUID
    var screenshotIDs: [UUID]
    var destination: URL
    // TODO: page size, ordering, progress, status.
}
