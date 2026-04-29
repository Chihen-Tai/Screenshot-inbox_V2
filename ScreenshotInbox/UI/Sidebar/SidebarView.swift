import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SidebarViewModel()
    @State private var targetedDropSelection: SidebarSelection?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appState.sidebarSelection) {
                Section {
                    ForEach(libraryItems) { item in
                        sidebarRow(item)
                    }
                } header: {
                    SidebarSectionView(title: "Library")
                }

                Section {
                    ForEach(collectionItems) { item in
                        sidebarRow(item)
                    }
                } header: {
                    collectionsHeader
                }

                Section {
                    ForEach(smartItems) { item in
                        SidebarItemView(item: item)
                    }
                } header: {
                    SidebarSectionView(title: "Smart Collections")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)

            settingsRow
        }
        .navigationSplitViewColumnWidth(
            min: Theme.Layout.sidebarMin,
            ideal: Theme.Layout.sidebarIdeal,
            max: Theme.Layout.sidebarMax
        )
    }

    private var settingsRow: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            Button {
                #if DEBUG
                print("[Settings] sidebar settings clicked")
                #endif
                openSettingsPreservingSelection()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.settingsAction.systemImage)
                        .font(.system(size: 13))
                        .frame(width: 20)
                        .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    Text(viewModel.settingsAction.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.SemanticColor.label)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Layout.sidebarRowHPadding)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.clear)
                        .padding(.horizontal, Theme.Layout.sidebarHorizontalInset)
                )
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }

    private func openSettingsPreservingSelection() {
        let preservedSelection = appState.sidebarSelection
        SettingsWindowOpener.open(appState: appState)
        if appState.sidebarSelection != preservedSelection {
            #if DEBUG
            print("[BUG] Settings should not load screenshots")
            print("[Settings] restoring destination after unexpected change: \(preservedSelection?.displayTitle ?? "nil")")
            #endif
            appState.sidebarSelection = preservedSelection
        }
        DispatchQueue.main.async {
            if appState.sidebarSelection != preservedSelection {
                #if DEBUG
                print("[BUG] Settings should not load screenshots")
                print("[Settings] restoring deferred destination: \(preservedSelection?.displayTitle ?? "nil")")
                #endif
                appState.sidebarSelection = preservedSelection
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem) -> some View {
        if acceptsInternalScreenshotDrop(item.selection) {
            SidebarItemView(
                item: item,
                isDropTargeted: targetedDropSelection == item.selection
            )
            .background(
                SidebarDropTargetView(
                    targetName: item.title,
                    onTargeted: { isTargeted in
                        targetedDropSelection = isTargeted ? item.selection : nil
                    },
                    onDrop: { ids in
                        handleInternalScreenshotDrop(ids, on: item.selection)
                    }
                )
            )
        } else {
            SidebarItemView(item: item)
        }
    }

    private func acceptsInternalScreenshotDrop(_ selection: SidebarSelection) -> Bool {
        switch selection {
        case .favorites, .trash, .collection:
            return true
        default:
            return false
        }
    }

    private func handleInternalScreenshotDrop(_ ids: [UUID], on selection: SidebarSelection) {
        guard acceptsInternalScreenshotDrop(selection), !ids.isEmpty else { return }
        print("[SidebarDrop] drop received IDs: \(ids.map(\.uuidString))")
        switch selection {
        case .favorites:
            print("[SidebarDrop] action called: favorite")
            appState.router.addDraggedScreenshotsToFavorites(ids: ids)
        case .trash:
            print("[SidebarDrop] action called: trash")
            appState.router.moveDraggedScreenshotsToTrash(ids: ids)
        case .collection(let uuid):
            print("[SidebarDrop] action called: collection \(uuid)")
            appState.router.addDraggedScreenshots(ids: ids, toCollection: uuid)
        default:
            break
        }
    }

    private var libraryItems: [SidebarItem] {
        [
            SidebarItem(selection: .inbox, title: "Inbox", systemImage: "tray", count: appState.inboxCount),
            SidebarItem(selection: .recent, title: "Recent", systemImage: "clock", count: appState.recentCount),
            SidebarItem(selection: .favorites, title: "Favorites", systemImage: "star", count: appState.favoriteCount),
            SidebarItem(selection: .untagged, title: "Untagged", systemImage: "tag.slash", count: appState.untaggedCount),
            SidebarItem(selection: .trash, title: "Trash", systemImage: "trash", count: appState.trashCount),
        ]
    }

    private var collectionItems: [SidebarItem] {
        appState.collections.map {
            SidebarItem(
                selection: .collection($0.uuid),
                title: $0.name,
                systemImage: $0.name == "Chemistry" ? "atom" : "folder",
                count: appState.collectionCount(forUUID: $0.uuid)
            )
        }
    }

    private var collectionsHeader: some View {
        HStack {
            SidebarSectionView(title: "Collections")
            Spacer(minLength: 0)
            Button {
                appState.router.newCollection()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            }
            .buttonStyle(.plain)
            .help("New Collection")
        }
    }

    private var smartItems: [SidebarItem] {
        [
            SidebarItem(selection: .smart(.ocrPending), title: "OCR Pending", systemImage: "text.viewfinder", count: appState.ocrPendingCount),
            SidebarItem(selection: .smart(.duplicates), title: "Duplicates", systemImage: "square.on.square", count: appState.duplicatesCount),
            SidebarItem(selection: .smart(.thisWeek), title: "This Week", systemImage: "calendar", count: appState.thisWeekCount),
        ]
    }
}
