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
                    ForEach(appState.collections, id: \.uuid) { collection in
                        collectionRow(collection)
                    }
                } header: {
                    collectionsHeader
                }

                Section {
                    ForEach(smartItems) { item in
                        SidebarItemView(item: item)
                            .contextMenu {
                                smartContextMenu(for: item)
                            }
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
                AppWindowRouter.shared.openSettings()
            } label: {
                SidebarItemView(
                    item: SidebarItem(
                        selection: .settings,
                        title: viewModel.settingsAction.title,
                        systemImage: viewModel.settingsAction.systemImage,
                        count: nil
                    )
                )
                .padding(.horizontal, Theme.Layout.sidebarHorizontalInset)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Layout.sidebarRowHPadding - Theme.Layout.sidebarHorizontalInset)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
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
            .contextMenu {
                libraryContextMenu(for: item)
            }
        } else {
            SidebarItemView(item: item)
                .contextMenu {
                    libraryContextMenu(for: item)
                }
        }
    }

    @ViewBuilder
    private func collectionRow(_ collection: ScreenshotCollection) -> some View {
        let selection = SidebarSelection.collection(collection.uuid)
        let item = SidebarItem(
            selection: selection,
            title: collection.name,
            systemImage: collection.name == "Chemistry" ? "atom" : "folder",
            count: appState.collectionCount(forUUID: collection.uuid)
        )

        Button {
            appState.sidebarSelection = selection
        } label: {
            SidebarItemView(
                item: item,
                isDropTargeted: targetedDropSelection == selection
            )
        }
        .buttonStyle(.plain)
        .tag(selection)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .background(
            SidebarDropTargetView(
                targetName: collection.name,
                targetCollectionUUID: collection.uuid,
                onTargeted: { isTargeted in
                    targetedDropSelection = isTargeted ? selection : nil
                },
                onDrop: { ids in
                    handleInternalScreenshotDrop(ids, on: selection)
                },
                onCollectionHover: { sourceUUID, position in
                    handleCollectionHover(sourceUUID: sourceUUID, targetUUID: collection.uuid, position: position)
                },
                onCollectionDrop: { sourceUUID, position in
                    handleCollectionDrop(sourceUUID: sourceUUID, targetUUID: collection.uuid, position: position)
                }
            )
        )
        .onDrag {
            let provider = NSItemProvider(
                item: InternalCollectionDrag.encode(collection.uuid).data(using: .utf8) as NSData?,
                typeIdentifier: InternalCollectionDrag.pasteboardTypeString
            )
            provider.registerObject(InternalCollectionDrag.encodeTextFallback(collection.uuid) as NSString, visibility: .ownProcess)
            provider.registerDataRepresentation(
                forTypeIdentifier: InternalCollectionDrag.pasteboardTypeString,
                visibility: .ownProcess
            ) { completion in
                completion(InternalCollectionDrag.encode(collection.uuid).data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .contextMenu {
            Button("Rename Collection") {
                appState.beginRenameCollection(collection)
            }
            Button("Delete Collection", role: .destructive) {
                appState.beginDeleteCollection(collection)
            }
            Divider()
            Button("Move Up") {
                appState.moveCollectionUp(collection)
            }
            .disabled(!appState.canMoveCollectionUp(collection))
            Button("Move Down") {
                appState.moveCollectionDown(collection)
            }
            .disabled(!appState.canMoveCollectionDown(collection))
            Divider()
            Button("Add Selected Screenshots to Collection") {
                appState.addScreenshots(ids: Array(appState.selectedScreenshotIDs), toCollection: collection.uuid)
            }
            .disabled(appState.selectedScreenshotIDs.isEmpty)
        }
    }

    @ViewBuilder
    private func libraryContextMenu(for item: SidebarItem) -> some View {
        switch item.selection {
        case .trash:
            Button("Open Trash") {
                appState.sidebarSelection = .trash
            }
            Divider()
            Button("Restore All") {
                appState.router.restoreAllFromTrash()
            }
            .disabled(appState.trashCount == 0)
            Button("Empty Trash", role: .destructive) {
                appState.router.emptyTrash()
            }
            .disabled(appState.trashCount == 0)
        case .inbox:
            Button("Open Inbox") { appState.sidebarSelection = .inbox }
        case .recent:
            Button("Open Recent") { appState.sidebarSelection = .recent }
        case .favorites:
            Button("Open Favorites") { appState.sidebarSelection = .favorites }
        case .untagged:
            Button("Open Untagged") { appState.sidebarSelection = .untagged }
        case .collection:
            Button("Open Collection") { appState.sidebarSelection = item.selection }
            Button("Export Collection…") {
                appState.sidebarSelection = item.selection
                appState.exportCurrentCollection()
            }
        case .smart, .settings:
            EmptyView()
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

    private func handleCollectionDrop(
        sourceUUID: String,
        targetUUID: String,
        position: SidebarCollectionDropPosition
    ) {
        appState.commitCollectionReorder(sourceUUID: sourceUUID, targetUUID: targetUUID, position: position)
    }

    private func handleCollectionHover(
        sourceUUID: String,
        targetUUID: String,
        position: SidebarCollectionDropPosition
    ) {
        switch position {
        case .before:
            appState.previewCollectionReorder(sourceUUID: sourceUUID, before: targetUUID)
        case .after:
            appState.previewCollectionReorder(sourceUUID: sourceUUID, after: targetUUID)
        }
    }

    private func handleInternalScreenshotDrop(_ ids: [UUID], on selection: SidebarSelection) {
        guard acceptsInternalScreenshotDrop(selection), !ids.isEmpty else { return }
        switch selection {
        case .favorites:
            appState.router.addDraggedScreenshotsToFavorites(ids: ids)
        case .trash:
            appState.router.moveDraggedScreenshotsToTrash(ids: ids)
        case .collection(let uuid):
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
        .contextMenu {
            Button("New Collection") {
                appState.router.newCollection()
            }
        }
    }

    @ViewBuilder
    private func smartContextMenu(for item: SidebarItem) -> some View {
        switch item.selection {
        case .smart(.ocrPending):
            Button("Refresh Count") {
                appState.refreshOCRState()
            }
            Button("Re-run OCR Pending") {
                let pending = appState.allScreenshots.filter { !$0.isTrashed && !$0.isOCRComplete }
                appState.rerunOCR(for: pending)
            }
            .disabled(appState.ocrPendingCount == 0)
        case .smart(.duplicates):
            Button("Rebuild Duplicate Index") {
                appState.rebuildDuplicateIndex()
            }
        case .smart(.thisWeek):
            Button("Show Criteria") {
                appState.showToast("Shows screenshots created in the last 7 days", kind: .info)
            }
        default:
            EmptyView()
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
