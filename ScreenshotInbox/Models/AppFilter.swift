import Foundation

/// Sidebar / search filter shape for Phase 3 routing.
enum AppFilter: Hashable {
    case all
    case inbox
    case collection(UUID)
    case tag(UUID)
    case trash
}

/// Chip filters above the grid.
enum FilterChip: String, CaseIterable, Hashable {
    case all = "All"
    case favorites = "Favorites"
    case ocrComplete = "OCR Complete"
    case tagged = "Tagged"
    case png = "PNG"
    case thisWeek = "This Week"
}

/// Concrete sidebar destinations for the prototype.
enum SidebarSelection: Hashable {
    case inbox, recent, favorites, untagged, trash
    case collection(String)
    case smart(SmartView)
    case settings

    var displayTitle: String {
        switch self {
        case .inbox: return "Inbox"
        case .recent: return "Recent"
        case .favorites: return "Favorites"
        case .untagged: return "Untagged"
        case .trash: return "Trash"
        case .collection(let n): return n
        case .smart(let v): return v.title
        case .settings: return "Settings"
        }
    }
}

enum SmartView: String, CaseIterable, Hashable {
    case ocrPending, duplicates, thisWeek
    var title: String {
        switch self {
        case .ocrPending: return "OCR Pending"
        case .duplicates: return "Duplicates"
        case .thisWeek: return "This Week"
        }
    }
}
