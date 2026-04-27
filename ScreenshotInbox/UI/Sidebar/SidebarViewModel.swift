import Foundation

struct SidebarItem: Identifiable, Hashable {
    let selection: SidebarSelection
    let title: String
    let systemImage: String
    let count: Int?
    var id: SidebarSelection { selection }
}

/// Thin Phase-2 view model that owns mock sidebar data.
/// Phase 3: replace with `LibraryService`-driven sections.
@MainActor
final class SidebarViewModel: ObservableObject {
    let library: [SidebarItem]
    let collections: [SidebarItem]
    let smart: [SidebarItem]
    let settingsItem: SidebarItem

    init() {
        self.library = [
            SidebarItem(selection: .inbox,     title: "Inbox",     systemImage: "tray",      count: 12),
            SidebarItem(selection: .recent,    title: "Recent",    systemImage: "clock",     count: nil),
            SidebarItem(selection: .favorites, title: "Favorites", systemImage: "star",      count: 3),
            SidebarItem(selection: .untagged,  title: "Untagged",  systemImage: "tag.slash", count: 4),
            SidebarItem(selection: .trash,     title: "Trash",     systemImage: "trash",     count: nil),
        ]
        self.collections = [
            SidebarItem(selection: .collection("Chemistry"), title: "Chemistry", systemImage: "atom",       count: 5),
            SidebarItem(selection: .collection("Papers"),    title: "Papers",    systemImage: "doc.text",   count: 4),
            SidebarItem(selection: .collection("UI Ideas"),  title: "UI Ideas",  systemImage: "paintbrush", count: 3),
            SidebarItem(selection: .collection("Temporary"), title: "Temporary", systemImage: "folder",     count: 2),
        ]
        self.smart = [
            SidebarItem(selection: .smart(.ocrPending), title: "OCR Pending", systemImage: "text.viewfinder",   count: 1),
            SidebarItem(selection: .smart(.duplicates), title: "Duplicates",  systemImage: "square.on.square",  count: 2),
            SidebarItem(selection: .smart(.thisWeek),   title: "This Week",   systemImage: "calendar",          count: 6),
        ]
        self.settingsItem = SidebarItem(selection: .settings, title: "Settings", systemImage: "gearshape", count: nil)
    }
}
