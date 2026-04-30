import Foundation
import Combine
import AppKit
import SwiftUI

/// Single source of truth for the prototype.
///
/// Owns: sidebar selection, filter chip, search query, layout mode, mock
/// screenshot store (mutable for Phase 5 mock trash + rename), selection
/// (delegated to `SelectionController`), preview / rename overlay state,
/// toast banner, and the central `ScreenshotActionRouter`.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Sidebar / filter / search

    @Published var sidebarSelection: SidebarSelection? = .inbox {
        didSet { pruneSelectionToVisible() }
    }
    @Published var activeFilterChip: FilterChip = .all
    @Published var searchQuery: String = ""
    @Published var preferences: AppPreferences {
        didSet {
            settingsService.save(preferences)
            applyPreferenceSideEffects(oldValue: oldValue)
        }
    }
    @Published var isAutoImportEnabled: Bool = AppPreferences.defaults.autoImportEnabled {
        didSet {
            if preferences.autoImportEnabled != isAutoImportEnabled {
                preferences.autoImportEnabled = isAutoImportEnabled
            }
            if isAutoImportEnabled {
                autoImportService.reloadWatchers()
            } else {
                autoImportService.stop()
            }
        }
    }
    @Published var gridThumbnailSize: GridThumbnailSize = AppPreferences.defaults.gridThumbnailSize {
        didSet {
            if preferences.gridThumbnailSize != gridThumbnailSize {
                preferences.gridThumbnailSize = gridThumbnailSize
            }
        }
    }
    @Published var screenshotSortField: ScreenshotSortField = AppPreferences.defaults.screenshotSortField {
        didSet {
            if preferences.screenshotSortField != screenshotSortField {
                preferences.screenshotSortField = screenshotSortField
            }
        }
    }
    @Published var screenshotSortDirection: SortDirection = AppPreferences.defaults.screenshotSortDirection {
        didSet {
            if preferences.screenshotSortDirection != screenshotSortDirection {
                preferences.screenshotSortDirection = screenshotSortDirection
            }
        }
    }

    // MARK: - Window-driven layout overrides

    @Published var layoutMode: Theme.LayoutMode = .regular
    @Published var sidebarOverrideVisible: Bool = false
    @Published var inspectorOverrideVisible: Bool = true
    @Published var sidebarPanelWidth: CGFloat = CGFloat(AppPreferences.defaults.sidebarPanelWidth) {
        didSet {
            let stored = Double(sidebarPanelWidth)
            if preferences.sidebarPanelWidth != stored {
                preferences.sidebarPanelWidth = stored
            }
        }
    }
    @Published var inspectorPanelWidth: CGFloat = CGFloat(AppPreferences.defaults.inspectorPanelWidth) {
        didSet {
            let stored = Double(inspectorPanelWidth)
            if preferences.inspectorPanelWidth != stored {
                preferences.inspectorPanelWidth = stored
            }
        }
    }

    // MARK: - Phase 5 overlays

    /// Mock Quick Look preview is shown when this is non-nil.
    @Published var previewedScreenshotID: UUID?
    @Published private(set) var previewSequenceIDs: [UUID] = []
    @Published var ocrTextViewerScreenshotID: UUID?
    /// Mock rename sheet is shown when this is non-nil.
    @Published var renamingScreenshotID: UUID?
    /// Live rename text-field value. Bound by the rename sheet.
    @Published var pendingRenameText: String = ""
    @Published var tagEditorTargetIDs: [UUID] = []
    @Published var pendingTagText: String = ""
    @Published var isTagEditorPresented: Bool = false
    @Published var collectionPickerTargetIDs: [UUID] = []
    @Published var isCollectionPickerPresented: Bool = false
    @Published var isCollectionRenamePresented: Bool = false
    @Published var collectionRenameTargetUUID: String?
    @Published var pendingCollectionName: String = ""
    @Published var collectionDeleteTarget: ScreenshotCollection?
    @Published var permanentDeleteTargetIDs: [UUID] = []
    @Published var isEmptyTrashDeletePending: Bool = false
    /// Currently displayed toast / banner. Auto-clears after a short delay.
    @Published var toast: ToastMessage?

    // MARK: - Selection / shortcuts

    let selection: SelectionController
    let shortcuts = WindowShortcutController()

    /// Phase 5 router. Set in `init` after self is fully constructed so it
    /// can hold an `unowned` ref back without ordering trouble.
    private(set) var router: ScreenshotActionRouter!
    let appUndoService = OperationHistoryService()

    // MARK: - Phase 6 persistence stack

    /// Real on-disk library. Always non-nil — bootstrap is best-effort and
    /// degrades to mock-only mode if it fails.
    private(set) var library: MacLibraryService
    /// Set when SQLite is reachable. `nil` means we're in mock-only mode and
    /// repository writes are no-ops.
    private(set) var database: Database?
    private(set) var repository: ScreenshotRepository
    private(set) var collectionRepository: CollectionRepository
    private(set) var tagRepository: TagRepository
    private(set) var importSourceRepository: ImportSourceRepository
    private(set) var ocrRepository: OCRRepository
    private(set) var detectedCodeRepository: DetectedCodeRepository
    private(set) var imageHashRepository: ImageHashRepository
    private(set) var organizationRuleRepository: OrganizationRuleRepository
    private(set) var settingsService: SettingsService
    private(set) var importService: ImportService
    private(set) var autoImportService: AutoImportService
    private(set) var ocrQueueService: OCRQueueService
    private(set) var codeDetectionQueueService: CodeDetectionQueueService
    private(set) var organizationRuleService: OrganizationRuleService
    private(set) var searchService: SearchService
    private(set) var duplicateDetectionService: DuplicateDetectionService
    private(set) var imageHashingService: ImageHashingService
    private(set) var pdfExportService: PDFExporting
    private(set) var exportShareService: ExportShareService
    private(set) var clipboardService: ScreenshotClipboardService!
    private(set) var libraryIntegrityService: LibraryIntegrityService
    private(set) var folderAccessService: FolderAccessService
    private(set) var thumbnailProvider: MacThumbnailProvider
    private(set) var fileActionService: MacFileActionService
    /// Legacy demo-mode flag. Runtime no longer seeds mock screenshots when
    /// SQLite is empty; this remains true only if persistence could not open.
    private(set) var isUsingMockData: Bool = true

    #if DEBUG
    @Published var showDebugControls: Bool = false
    #endif

    // MARK: - Screenshot store

    /// Canonical newest-first id order. Order is stable across mutations —
    /// only `screenshotsByID` changes when a row is renamed or trashed.
    private var orderedIDs: [UUID]
    private var screenshotsByID: [UUID: Screenshot]
    @Published private(set) var collections: [ScreenshotCollection] = []
    @Published private(set) var collectionCountsByUUID: [String: Int] = [:]
    @Published private(set) var importSources: [ImportSource] = []
    @Published private(set) var ocrResultsByScreenshotUUID: [String: OCRResult] = [:]
    @Published private(set) var detectedCodesByScreenshotUUID: [String: [DetectedCode]] = [:]
    @Published private(set) var imageHashesByScreenshotUUID: [String: ImageHashRecord] = [:]
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var organizationRules: [OrganizationRule] = []
    @Published private(set) var libraryIntegrityReport: LibraryIntegrityReport?
    @Published private(set) var maintenanceStatusText: String?
    @Published private(set) var isMaintenanceRunning: Bool = false
    @Published var isPDFExportSheetPresented: Bool = false
    @Published var isPDFExporting: Bool = false
    @Published var pdfExportOptions: PDFExportOptions = .defaults(outputPath: "")
    @Published var pdfExportTargetIDs: [UUID] = []
    private var collectionScreenshotIDsByUUID: [String: Set<UUID>] = [:]
    private var collectionNamesByScreenshotID: [UUID: [String]] = [:]

    /// All screenshots in the canonical order, including trashed.
    var allScreenshots: [Screenshot] {
        orderedIDs.compactMap { screenshotsByID[$0] }
    }

    func screenshots(for ids: [UUID]) -> [Screenshot] {
        ids.compactMap { screenshotsByID[$0] }
    }

    // MARK: - Internals

    private var selectionForwarder: AnyCancellable?
    private var toastDismissTask: Task<Void, Never>?
    private var isPerformingUndo = false
    private var pendingToastUndoTitle: String?
    #if DEBUG
    private static func ensureDevelopmentImportSources(
        in repository: ImportSourceRepository,
        libraryRootURL: URL
    ) throws {
        let existing = try repository.fetchAll()
        guard existing.isEmpty else { return }
        let fileManager = FileManager.default
        let candidates = [
            fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ].compactMap { $0?.standardizedFileURL }
        let libraryPath = libraryRootURL.standardizedFileURL.path
        for url in candidates {
            let path = url.path
            guard path != libraryPath, !path.hasPrefix(libraryPath + "/") else { continue }
            _ = try repository.create(
                folderPath: path,
                displayName: url.lastPathComponent,
                recursive: false
            )
            #if DEBUG
            print("[AutoImport] development default source added: \(path)")
            #endif
        }
    }
    #endif

    // MARK: - Init

    init() {
        // Build the persistence stack first so the rest of init knows whether
        // we're in real-data or mock-only mode.
        let library = MacLibraryService()
        self.library = library
        let settingsService = SettingsService()
        let loadedPreferences = settingsService.preferences
        self.settingsService = settingsService
        self.preferences = loadedPreferences
        self.isAutoImportEnabled = loadedPreferences.autoImportEnabled
        self.gridThumbnailSize = loadedPreferences.gridThumbnailSize
        self.screenshotSortField = loadedPreferences.screenshotSortField
        self.screenshotSortDirection = loadedPreferences.screenshotSortDirection
        self.sidebarOverrideVisible = loadedPreferences.sidebarVisibleByDefault
        self.inspectorOverrideVisible = loadedPreferences.inspectorVisibleByDefault
        self.sidebarPanelWidth = CGFloat(loadedPreferences.sidebarPanelWidth)
        self.inspectorPanelWidth = CGFloat(loadedPreferences.inspectorPanelWidth)
        #if DEBUG
        self.showDebugControls = loadedPreferences.showDebugControls
        #endif

        var database: Database? = nil
        var repository = ScreenshotRepository()
        var collectionRepository = CollectionRepository()
        var tagRepository = TagRepository()
        var importSourceRepository = ImportSourceRepository()
        var ocrRepository = OCRRepository()
        var detectedCodeRepository = DetectedCodeRepository()
        var imageHashRepository = ImageHashRepository()
        var organizationRuleRepository = OrganizationRuleRepository()
        var loaded: [Screenshot] = []
        var loadedCollections: [ScreenshotCollection] = []
        var loadedCollectionCounts: [String: Int] = [:]
        var loadedCollectionMemberships: [String: Set<UUID>] = [:]
        var loadedTagsByScreenshotUUID: [String: [Tag]] = [:]
        var loadedImportSources: [ImportSource] = []
        var loadedOCRResults: [String: OCRResult] = [:]
        var loadedDetectedCodes: [String: [DetectedCode]] = [:]
        var loadedImageHashes: [String: ImageHashRecord] = [:]
        var loadedOrganizationRules: [OrganizationRule] = []

        do {
            try library.bootstrap()
            let db = try Database(path: library.databaseURL.path)
            let migrations = MigrationManager()
            migrations.register(.initialSchema)
            migrations.register(.organizationSchema)
            migrations.register(.autoImportSchema)
            migrations.register(.ocrSchema)
            migrations.register(.detectedCodesSchema)
            migrations.register(.imageHashesSchema)
            migrations.register(.collectionSortIndexSchema)
            migrations.register(.organizationRulesSchema)
            try migrations.runPending(on: db)

            let repo = ScreenshotRepository(database: db)
            let collectionsRepo = CollectionRepository(database: db)
            let tagsRepo = TagRepository(database: db)
            let importSourcesRepo = ImportSourceRepository(database: db)
            let ocrRepo = OCRRepository(database: db)
            let codesRepo = DetectedCodeRepository(database: db)
            let imageHashesRepo = ImageHashRepository(database: db)
            let rulesRepo = OrganizationRuleRepository(database: db)
            try collectionsRepo.ensureDefaultCollections()
            #if DEBUG
            // TODO: Replace development default Desktop/Downloads watchers with user-configurable Auto Import settings before release.
            try Self.ensureDevelopmentImportSources(in: importSourcesRepo, libraryRootURL: library.libraryRootURL)
            #endif
            loaded = try repo.fetchAll(includeTrashed: true)
            try ocrRepo.ensurePending(for: loaded.map(\.uuidString))
            loadedTagsByScreenshotUUID = try tagsRepo.tagsByScreenshotUUID()
            loadedOCRResults = Dictionary(uniqueKeysWithValues: try ocrRepo.fetchAll().map { ($0.screenshotUUID, $0) })
            loadedDetectedCodes = Dictionary(grouping: try codesRepo.fetchAll(), by: \.screenshotUUID)
            loadedImageHashes = try imageHashesRepo.fetchAll()
            loadedOrganizationRules = try rulesRepo.fetchAll()
            loadedCollections = try collectionsRepo.fetchCollections()
            loadedCollectionCounts = try collectionsRepo.countsByCollectionUUID()
            loadedImportSources = try importSourcesRepo.fetchAll()
            for collection in loadedCollections {
                let shots = try collectionsRepo.fetchScreenshots(inCollection: collection.uuid)
                loadedCollectionMemberships[collection.uuid] = Set(shots.map(\.id))
            }

            database = db
            repository = repo
            collectionRepository = collectionsRepo
            tagRepository = tagsRepo
            importSourceRepository = importSourcesRepo
            ocrRepository = ocrRepo
            detectedCodeRepository = codesRepo
            imageHashRepository = imageHashesRepo
            organizationRuleRepository = rulesRepo
            #if DEBUG
            print("[AppState] persistence ok: rows=\(loaded.count) at \(library.databaseURL.path)")
            #endif
        } catch {
            print("[AppState] persistence bootstrap failed — falling back to mocks: \(error)")
        }
        self.database = database
        self.repository = repository
        self.collectionRepository = collectionRepository
        self.tagRepository = tagRepository
        self.importSourceRepository = importSourceRepository
        self.ocrRepository = ocrRepository
        self.detectedCodeRepository = detectedCodeRepository
        self.imageHashRepository = imageHashRepository
        self.organizationRuleRepository = organizationRuleRepository

        let metadataReader: ImageMetadataReading = MacImageMetadataReader()
        let thumbnailService: ThumbnailGenerating = MacThumbnailService(library: library)
        self.importService = ImportService(
            library: library,
            repository: repository,
            metadataReader: metadataReader,
            thumbnailService: thumbnailService
        )
        self.autoImportService = AutoImportService(
            importService: self.importService,
            importSourceRepository: importSourceRepository,
            fileWatcher: MacFileWatcherService(),
            libraryRootURL: library.libraryRootURL
        )
        let ocrService = MacOCRService(library: library) { [weak settingsService] in
            settingsService?.preferences.ocrPreferredLanguages ?? AppPreferences.defaults.ocrPreferredLanguages
        }
        self.ocrQueueService = OCRQueueService(
            repository: ocrRepository,
            screenshotRepository: repository,
            ocrService: ocrService
        )
        let codeDetectionService = MacCodeDetectionService(library: library)
        self.codeDetectionQueueService = CodeDetectionQueueService(
            repository: detectedCodeRepository,
            screenshotRepository: repository,
            detectionService: codeDetectionService
        )
        self.organizationRuleService = OrganizationRuleService(
            ruleRepository: organizationRuleRepository,
            screenshotRepository: repository,
            tagRepository: tagRepository,
            collectionRepository: collectionRepository,
            ocrRepository: ocrRepository,
            detectedCodeRepository: detectedCodeRepository
        )
        self.searchService = SearchService()
        self.duplicateDetectionService = DuplicateDetectionService(
            screenshotRepository: repository,
            imageHashRepository: imageHashRepository
        )
        self.imageHashingService = MacImageHashingService()
        self.pdfExportService = MacPDFExportService(library: library)
        self.exportShareService = ExportShareService(libraryRootURL: library.libraryRootURL)
        self.folderAccessService = FolderAccessService()
        self.libraryIntegrityService = LibraryIntegrityService(
            library: library,
            screenshotRepository: repository,
            ocrRepository: ocrRepository,
            imageHashRepository: imageHashRepository,
            thumbnailService: thumbnailService,
            database: database
        )
        self.thumbnailProvider = MacThumbnailProvider(library: library)
        self.fileActionService = MacFileActionService()

        // Real rows take precedence. An empty database now renders an empty
        // library instead of mixing runtime demo cards into real-data mode.
        if !loaded.isEmpty {
            for index in loaded.indices {
                loaded[index].tags = loadedTagsByScreenshotUUID[loaded[index].id.uuidString.lowercased()]?.map(\.name) ?? []
                Self.applyOCR(loadedOCRResults[loaded[index].uuidString], to: &loaded[index])
            }
            self.orderedIDs = loaded.map(\.id)
            self.screenshotsByID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            self.isUsingMockData = false
        } else {
            self.orderedIDs = []
            self.screenshotsByID = [:]
            self.isUsingMockData = database == nil
        }
        self.collections = loadedCollections
        self.collectionCountsByUUID = loadedCollectionCounts
        self.collectionScreenshotIDsByUUID = loadedCollectionMemberships
        self.importSources = loadedImportSources
        self.ocrResultsByScreenshotUUID = loadedOCRResults
        self.detectedCodesByScreenshotUUID = loadedDetectedCodes
        self.imageHashesByScreenshotUUID = loadedImageHashes
        self.organizationRules = loadedOrganizationRules
        self.duplicateGroups = Self.makeDuplicateGroups(
            screenshots: loaded,
            imageHashes: loadedImageHashes
        )

        let controller = SelectionController()
        self.selection = controller

        // Forward selection changes so anyone observing AppState updates too.
        self.selectionForwarder = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        self.router = ScreenshotActionRouter(appState: self)
        self.clipboardService = ScreenshotClipboardService(
            screenshotsProvider: { [weak self] ids in
                guard let self else { return [] }
                let requested = Set(ids.compactMap(UUID.init(uuidString:)))
                return self.filteredScreenshots.filter { requested.contains($0.id) }
            },
            libraryRootURL: library.libraryRootURL,
            importService: self.importService
        )

        // Pre-seed one item so the inspector populates on launch.
        if let first = allScreenshots.first {
            controller.replace(with: first.id)
        }
        print("[AppState] init instance:", ObjectIdentifier(self), "mock=\(isUsingMockData)")
        startAutoImport()
        startOCRQueue()
        startCodeDetectionQueue()
        rebuildMissingDuplicateHashes()
    }

    private func applyPreferenceSideEffects(oldValue: AppPreferences) {
        if oldValue.inspectorVisibleByDefault != preferences.inspectorVisibleByDefault {
            inspectorOverrideVisible = preferences.inspectorVisibleByDefault
        }
        if oldValue.sidebarVisibleByDefault != preferences.sidebarVisibleByDefault {
            sidebarOverrideVisible = preferences.sidebarVisibleByDefault
        }
        if oldValue.sidebarPanelWidth != preferences.sidebarPanelWidth,
           sidebarPanelWidth != CGFloat(preferences.sidebarPanelWidth) {
            sidebarPanelWidth = CGFloat(preferences.sidebarPanelWidth)
        }
        if oldValue.inspectorPanelWidth != preferences.inspectorPanelWidth,
           inspectorPanelWidth != CGFloat(preferences.inspectorPanelWidth) {
            inspectorPanelWidth = CGFloat(preferences.inspectorPanelWidth)
        }
        if oldValue.autoImportEnabled != preferences.autoImportEnabled,
           isAutoImportEnabled != preferences.autoImportEnabled {
            isAutoImportEnabled = preferences.autoImportEnabled
        }
        if oldValue.gridThumbnailSize != preferences.gridThumbnailSize,
           gridThumbnailSize != preferences.gridThumbnailSize {
            gridThumbnailSize = preferences.gridThumbnailSize
        }
        if oldValue.screenshotSortField != preferences.screenshotSortField,
           screenshotSortField != preferences.screenshotSortField {
            screenshotSortField = preferences.screenshotSortField
        }
        if oldValue.screenshotSortDirection != preferences.screenshotSortDirection,
           screenshotSortDirection != preferences.screenshotSortDirection {
            screenshotSortDirection = preferences.screenshotSortDirection
        }
        #if DEBUG
        if oldValue.showDebugControls != preferences.showDebugControls {
            showDebugControls = preferences.showDebugControls
        }
        #endif
    }

    // MARK: - Filtering

    /// Visible-in-grid screenshots after sidebar + filter chip + trash rules.
    /// Trash sidebar shows trashed only; everything else hides trashed.
    var filteredScreenshots: [Screenshot] {
        let parsedSearch = searchService.parsedQuery(searchQuery)
        let nonTrashed = allScreenshots.filter { !$0.isTrashed }
        let base: [Screenshot]
        if parsedSearch.includesTrashedScope {
            base = allScreenshots.filter(\.isTrashed)
        } else {
            switch sidebarSelection {
            case .inbox, .recent, nil:
                base = nonTrashed
            case .favorites:
                base = nonTrashed.filter(\.isFavorite)
            case .untagged:
                base = nonTrashed.filter { $0.tags.isEmpty }
            case .trash:
                base = allScreenshots.filter(\.isTrashed)
            case .collection(let uuid):
                let ids = collectionScreenshotIDsByUUID[uuid] ?? []
                base = nonTrashed.filter { ids.contains($0.id) }
            case .smart(.ocrPending):
                base = nonTrashed.filter { !$0.isOCRComplete }
            case .smart(.duplicates):
                let duplicateIDs = Set(duplicateGroups.flatMap(\.screenshotUUIDs))
                base = nonTrashed.filter { duplicateIDs.contains($0.uuidString) }
            case .smart(.thisWeek):
                let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
                base = nonTrashed.filter { $0.createdAt > cutoff }
            }
        }

        let chipFiltered: [Screenshot]
        switch activeFilterChip {
        case .all:         chipFiltered = base
        case .favorites:   chipFiltered = base.filter(\.isFavorite)
        case .ocrComplete: chipFiltered = base.filter(\.isOCRComplete)
        case .ocrPending:  chipFiltered = base.filter { !$0.isOCRComplete }
        case .tagged:      chipFiltered = base.filter { !$0.tags.isEmpty }
        case .untagged:    chipFiltered = base.filter { $0.tags.isEmpty }
        case .png:         chipFiltered = base.filter { $0.format == "PNG" }
        case .jpg:         chipFiltered = base.filter { $0.format == "JPG" || $0.format == "JPEG" }
        case .heic:        chipFiltered = base.filter { $0.format == "HEIC" || $0.format == "HEIF" }
        case .hasQRCode:
            chipFiltered = base.filter { !(detectedCodesByScreenshotUUID[$0.uuidString] ?? []).isEmpty }
        case .hasURL:
            chipFiltered = base.filter { (detectedCodesByScreenshotUUID[$0.uuidString] ?? []).contains(where: \.isURL) }
        case .today:
            chipFiltered = base.filter { Calendar.current.isDateInToday($0.createdAt) }
        case .thisWeek:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            chipFiltered = base.filter { $0.createdAt > cutoff }
        }
        let searched = searchService.filter(
            chipFiltered,
            query: searchQuery,
            collectionNamesByScreenshotID: collectionNamesByScreenshotID,
            detectedCodesByScreenshotID: detectedCodesByScreenshotUUID
        )
        return sortedScreenshots(searched)
    }

    var enabledQuickFilterChips: [FilterChip] {
        preferences.quickFilters.filter(\.isEnabled).map(\.chip)
    }

    func resetQuickFiltersToDefaults() {
        preferences.quickFilters = AppPreferences.defaultQuickFilters
        if !enabledQuickFilterChips.contains(activeFilterChip) {
            activeFilterChip = .all
        }
    }

    func moveQuickFilter(fromOffsets source: IndexSet, toOffset destination: Int) {
        preferences.quickFilters.move(fromOffsets: source, toOffset: destination)
    }

    func moveQuickFilterUp(_ filter: QuickFilterPreference) {
        guard let index = preferences.quickFilters.firstIndex(of: filter), index > 0 else { return }
        preferences.quickFilters.swapAt(index, index - 1)
    }

    func moveQuickFilterDown(_ filter: QuickFilterPreference) {
        guard let index = preferences.quickFilters.firstIndex(of: filter),
              index < preferences.quickFilters.count - 1 else { return }
        preferences.quickFilters.swapAt(index, index + 1)
    }

    private func sortedScreenshots(_ screenshots: [Screenshot]) -> [Screenshot] {
        screenshots.sorted { left, right in
            let comparison: ComparisonResult
            switch screenshotSortField {
            case .createdDate:
                if left.createdAt == right.createdAt {
                    comparison = left.name.localizedStandardCompare(right.name)
                } else {
                    comparison = left.createdAt < right.createdAt ? .orderedAscending : .orderedDescending
                }
            case .name:
                let nameOrder = left.name.localizedStandardCompare(right.name)
                comparison = nameOrder == .orderedSame
                    ? (left.createdAt < right.createdAt ? .orderedAscending : .orderedDescending)
                    : nameOrder
            case .size:
                if left.byteSize == right.byteSize {
                    comparison = left.name.localizedStandardCompare(right.name)
                } else {
                    comparison = left.byteSize < right.byteSize ? .orderedAscending : .orderedDescending
                }
            }
            switch comparison {
            case .orderedAscending:
                return screenshotSortDirection == .ascending
            case .orderedDescending:
                return screenshotSortDirection == .descending
            case .orderedSame:
                return left.id.uuidString < right.id.uuidString
            }
        }
    }

    var displayTitle: String {
        if case .collection(let uuid)? = sidebarSelection {
            return collectionName(forUUID: uuid) ?? "Collection"
        }
        return sidebarSelection?.displayTitle ?? "Inbox"
    }

    var inboxCount: Int {
        allScreenshots.filter { !$0.isTrashed }.count
    }

    var recentCount: Int {
        inboxCount
    }

    var favoriteCount: Int {
        allScreenshots.filter { !$0.isTrashed && $0.isFavorite }.count
    }

    var untaggedCount: Int {
        allScreenshots.filter { !$0.isTrashed && $0.tags.isEmpty }.count
    }

    var trashCount: Int {
        allScreenshots.filter(\.isTrashed).count
    }

    var ocrPendingCount: Int {
        allScreenshots.filter {
            !$0.isTrashed && (ocrResultsByScreenshotUUID[$0.uuidString]?.status == .pending ||
                              ocrResultsByScreenshotUUID[$0.uuidString]?.status == .processing ||
                              ocrResultsByScreenshotUUID[$0.uuidString] == nil)
        }.count
    }

    var duplicatesCount: Int {
        Set(duplicateGroups.flatMap(\.screenshotUUIDs)).count
    }

    var thisWeekCount: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return allScreenshots.filter { !$0.isTrashed && $0.createdAt > cutoff }.count
    }

    func collectionName(forUUID uuid: String) -> String? {
        collections.first(where: { $0.uuid == uuid })?.name
    }

    func collectionCount(forUUID uuid: String) -> Int {
        collectionCountsByUUID[uuid] ?? 0
    }

    func duplicateGroup(containing screenshotID: UUID) -> DuplicateGroup? {
        let uuid = screenshotID.uuidString.lowercased()
        return duplicateGroups.first { $0.screenshotUUIDs.contains(uuid) }
    }

    func recommendedKeepID(for group: DuplicateGroup) -> UUID? {
        group.recommendedKeepUUID.flatMap(UUID.init(uuidString:))
    }

    func duplicateExtrasKeepingRecommended() -> [Screenshot] {
        duplicateGroups.flatMap { group in
            let keep = group.recommendedKeepUUID
            return group.screenshotUUIDs
                .filter { $0 != keep }
                .compactMap { UUID(uuidString: $0) }
                .compactMap { screenshotsByID[$0] }
                .filter { !$0.isTrashed }
        }
    }

    func trashDuplicateExtrasKeepingRecommended() {
        let extras = duplicateExtrasKeepingRecommended()
        guard !extras.isEmpty else {
            showToast("No duplicate extras to move", kind: .info)
            return
        }
        router.moveToTrash(extras)
        refreshDuplicateGroups()
    }

    func keepSelectedDuplicateAndTrashGroupExtras() {
        guard let selected = primarySelection,
              let group = duplicateGroup(containing: selected.id) else {
            showToast("Select a duplicate to keep", kind: .info)
            return
        }
        let extras = group.screenshotUUIDs
            .compactMap { UUID(uuidString: $0) }
            .filter { $0 != selected.id }
            .compactMap { screenshotsByID[$0] }
            .filter { !$0.isTrashed }
        guard !extras.isEmpty else {
            showToast("No other duplicates in this group", kind: .info)
            return
        }
        router.moveToTrash(extras)
        refreshDuplicateGroups()
    }

    func createNewCollection(promptForName: Bool = true) {
        let name = nextCollectionName()
        do {
            let collection = try collectionRepository.createCollection(name: name)
            refreshOrganizationState(pruneSelection: false)
            sidebarSelection = .collection(collection.uuid)
            if promptForName {
                beginRenameCollection(collection)
            } else {
                showToast("Created collection \(collection.name)", kind: .success)
            }
        } catch {
            print("[AppState] create collection failed: \(error)")
            showToast("Could not create collection", kind: .info)
        }
    }

    func beginRenameCollection(_ collection: ScreenshotCollection) {
        collectionRenameTargetUUID = collection.uuid
        pendingCollectionName = collection.name
        isCollectionRenamePresented = true
    }

    func cancelCollectionRename() {
        isCollectionRenamePresented = false
        collectionRenameTargetUUID = nil
        pendingCollectionName = ""
    }

    func commitCollectionRename() {
        guard let uuid = collectionRenameTargetUUID else { return }
        let name = pendingCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try collectionRepository.renameCollection(uuid: uuid, name: name)
            refreshOrganizationState(pruneSelection: false)
            cancelCollectionRename()
            showToast("Renamed collection", kind: .success)
        } catch CollectionRepositoryError.emptyName {
            showToast("Collection name cannot be empty", kind: .info)
        } catch CollectionRepositoryError.duplicateName {
            showToast("A collection with that name already exists", kind: .info)
        } catch {
            print("[AppState] rename collection failed: \(error)")
            showToast("Could not rename collection", kind: .info)
        }
    }

    func beginDeleteCollection(_ collection: ScreenshotCollection) {
        collectionDeleteTarget = collection
    }

    func cancelDeleteCollection() {
        collectionDeleteTarget = nil
    }

    func confirmDeleteCollection() {
        guard let collection = collectionDeleteTarget else { return }
        do {
            try collectionRepository.deleteCollection(uuid: collection.uuid)
            if sidebarSelection == .collection(collection.uuid) {
                sidebarSelection = .inbox
            }
            refreshOrganizationState(pruneSelection: true)
            collectionDeleteTarget = nil
            showToast("Deleted collection \(collection.name)", kind: .success)
        } catch {
            print("[AppState] delete collection failed: \(error)")
            showToast("Could not delete collection", kind: .info)
        }
    }

    func moveCollectionUp(_ collection: ScreenshotCollection) {
        guard let index = collections.firstIndex(where: { $0.uuid == collection.uuid }),
              index > 0 else { return }
        var reordered = collections
        reordered.swapAt(index, index - 1)
        persistCollectionOrder(reordered, reloadSidebar: true)
    }

    func moveCollectionDown(_ collection: ScreenshotCollection) {
        guard let index = collections.firstIndex(where: { $0.uuid == collection.uuid }),
              index < collections.count - 1 else { return }
        var reordered = collections
        reordered.swapAt(index, index + 1)
        persistCollectionOrder(reordered, reloadSidebar: true)
    }

    func canMoveCollectionUp(_ collection: ScreenshotCollection) -> Bool {
        guard let index = collections.firstIndex(where: { $0.uuid == collection.uuid }) else { return false }
        return index > 0
    }

    func canMoveCollectionDown(_ collection: ScreenshotCollection) -> Bool {
        guard let index = collections.firstIndex(where: { $0.uuid == collection.uuid }) else { return false }
        return index < collections.count - 1
    }

    func reorderCollection(sourceUUID: String, before targetUUID: String) {
        guard previewCollectionReorder(sourceUUID: sourceUUID, before: targetUUID) else {
            return
        }
        persistCollectionOrder(collections, reloadSidebar: true)
    }

    func reorderCollection(sourceUUID: String, after targetUUID: String) {
        guard previewCollectionReorder(sourceUUID: sourceUUID, after: targetUUID) else {
            return
        }
        persistCollectionOrder(collections, reloadSidebar: true)
    }

    func commitCollectionReorder(
        sourceUUID: String,
        targetUUID: String,
        position: SidebarCollectionDropPosition
    ) {
        guard sourceUUID != targetUUID,
              isManualCollection(uuid: sourceUUID),
              isManualCollection(uuid: targetUUID) else {
            return
        }
        _ = previewCollectionReorder(sourceUUID: sourceUUID, targetUUID: targetUUID, position: position)
        persistCollectionOrder(collections, reloadSidebar: true)
    }

    @discardableResult
    func previewCollectionReorder(sourceUUID: String, before targetUUID: String) -> Bool {
        previewCollectionReorder(sourceUUID: sourceUUID, targetUUID: targetUUID, position: .before)
    }

    @discardableResult
    func previewCollectionReorder(sourceUUID: String, after targetUUID: String) -> Bool {
        previewCollectionReorder(sourceUUID: sourceUUID, targetUUID: targetUUID, position: .after)
    }

    @discardableResult
    private func previewCollectionReorder(
        sourceUUID: String,
        targetUUID: String,
        position: SidebarCollectionDropPosition
    ) -> Bool {
        guard sourceUUID != targetUUID,
              let sourceIndex = collections.firstIndex(where: { $0.uuid == sourceUUID }),
              let targetIndex = collections.firstIndex(where: { $0.uuid == targetUUID }),
              collections[sourceIndex].type == "manual",
              collections[targetIndex].type == "manual" else {
            return false
        }
        var reordered = collections
        let moving = reordered.remove(at: sourceIndex)
        let insertIndex: Int
        switch position {
        case .before:
            insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        case .after:
            insertIndex = min(sourceIndex < targetIndex ? targetIndex : targetIndex + 1, reordered.count)
        }
        guard insertIndex >= 0, insertIndex <= reordered.count else { return false }
        reordered.insert(moving, at: insertIndex)
        let currentOrder = collections.map(\.uuid)
        let finalOrder = reordered.map(\.uuid)
        guard currentOrder != finalOrder else { return false }
        #if DEBUG
        print("[CollectionReorder] hover from index=\(sourceIndex) to index=\(insertIndex)")
        #endif
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            collections = reordered
        }
        #if DEBUG
        print("[CollectionReorder] local order updated")
        print("[CollectionReorder] local order: \(finalOrder)")
        #endif
        return true
    }

    private func isManualCollection(uuid: String) -> Bool {
        collections.contains { $0.uuid == uuid && $0.type == "manual" }
    }

    private func persistCollectionOrder(_ reordered: [ScreenshotCollection], reloadSidebar: Bool) {
        let finalOrder = reordered.map(\.uuid)
        guard !finalOrder.isEmpty else { return }
        do {
            #if DEBUG
            print("[CollectionReorder] commit order: \(finalOrder)")
            #endif
            try collectionRepository.updateSortOrder(collectionUUIDsInOrder: finalOrder)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                collections = reordered.enumerated().map { index, collection in
                    var updated = collection
                    updated.sortIndex = Double(index)
                    updated.updatedAt = Date()
                    return updated
                }
            }
            #if DEBUG
            print("[CollectionReorder] saved sort_index")
            #endif
            if reloadSidebar {
                collections = try collectionRepository.fetchCollections()
                #if DEBUG
                print("[CollectionReorder] reload sidebar")
                #endif
            }
            objectWillChange.send()
        } catch {
            print("[AppState] reorder collections failed: \(error)")
            showToast("Could not reorder collections", kind: .info)
        }
    }

    func beginAddTag(to shots: [Screenshot]) {
        let ids = shots.map(\.id)
        guard !ids.isEmpty else { return }
        closeOverlayIfPresent()
        tagEditorTargetIDs = ids
        pendingTagText = ""
        isTagEditorPresented = true
    }

    func cancelTagEditor() {
        isTagEditorPresented = false
        tagEditorTargetIDs = []
        pendingTagText = ""
    }

    func commitPendingTag() {
        let name = pendingTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showToast("Tag name cannot be empty", kind: .info)
            return
        }
        addTag(named: name, to: tagEditorTargetIDs)
        cancelTagEditor()
    }

    func beginAddToCollection(_ shots: [Screenshot]) {
        let ids = shots.map(\.id)
        guard !ids.isEmpty else { return }
        closeOverlayIfPresent()
        collectionPickerTargetIDs = ids
        isCollectionPickerPresented = true
    }

    func cancelCollectionPicker() {
        isCollectionPickerPresented = false
        collectionPickerTargetIDs = []
    }

    func addPendingScreenshots(to collection: ScreenshotCollection) {
        addScreenshots(ids: collectionPickerTargetIDs, toCollection: collection.uuid)
        cancelCollectionPicker()
    }

    func addTag(named name: String, to ids: [UUID]) {
        let screenshotUUIDs = ids.map { $0.uuidString.lowercased() }
        guard !screenshotUUIDs.isEmpty else { return }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newlyTaggedIDs = ids.filter { id in
            let existing = screenshotsByID[id]?.tags ?? []
            return !existing.contains { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        }
        do {
            try tagRepository.addTag(name: name, toScreenshots: screenshotUUIDs)
            refreshOrganizationState(pruneSelection: false)
            if !isPerformingUndo, !newlyTaggedIDs.isEmpty,
               let tag = try tagRepository.fetchTags().first(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) {
                registerUndo(title: "Add Tag") { [weak self] in
                    self?.removeTagForUndo(uuid: tag.uuid, from: newlyTaggedIDs)
                }
            }
            let n = ids.count
            showToast(n == 1 ? "Added tag \(name)" : "Tagged \(n) screenshots with \(name)",
                      kind: .success)
        } catch TagRepositoryError.emptyName {
            showToast("Tag name cannot be empty", kind: .info)
        } catch {
            print("[AppState] add tag failed: \(error)")
            showToast("Could not add tag", kind: .info)
        }
    }

    func removeTag(uuid tagUUID: String, from ids: [UUID], name: String) {
        let screenshotUUIDs = ids.map { $0.uuidString.lowercased() }
        guard !screenshotUUIDs.isEmpty else { return }
        do {
            try tagRepository.removeTag(tagUUID: tagUUID, fromScreenshots: screenshotUUIDs)
            refreshOrganizationState(pruneSelection: false)
            showToast("Removed tag \(name)", kind: .success)
        } catch {
            print("[AppState] remove tag failed: \(error)")
            showToast("Could not remove tag", kind: .info)
        }
    }

    func addScreenshots(ids: [UUID], toCollection collectionUUID: String) {
        let screenshotUUIDs = ids.map { $0.uuidString.lowercased() }
        guard !screenshotUUIDs.isEmpty else { return }
        let existingIDs = collectionScreenshotIDsByUUID[collectionUUID] ?? []
        let newlyAddedIDs = ids.filter { !existingIDs.contains($0) }
        do {
            try collectionRepository.addScreenshots(screenshotUUIDs, toCollection: collectionUUID)
            refreshOrganizationState(pruneSelection: false)
            if !isPerformingUndo, !newlyAddedIDs.isEmpty {
                registerUndo(title: "Add to Collection") { [weak self] in
                    self?.removeScreenshotsFromCollectionForUndo(ids: newlyAddedIDs, collectionUUID: collectionUUID)
                }
            }
            let name = collectionName(forUUID: collectionUUID) ?? "Collection"
            let n = ids.count
            showToast("Added \(n) screenshot\(n == 1 ? "" : "s") to \(name)",
                      kind: .success)
        } catch {
            print("[AppState] add to collection failed: \(error)")
            showToast("Could not add to collection", kind: .info)
        }
    }

    func refreshOrganizationState(pruneSelection: Bool = true) {
        do {
            collections = try collectionRepository.fetchCollections()
            collectionCountsByUUID = try collectionRepository.countsByCollectionUUID()
            var memberships: [String: Set<UUID>] = [:]
            var namesByScreenshotID: [UUID: [String]] = [:]
            for collection in collections {
                let shots = try collectionRepository.fetchScreenshots(inCollection: collection.uuid)
                let ids = Set(shots.map(\.id))
                memberships[collection.uuid] = ids
                for id in ids {
                    namesByScreenshotID[id, default: []].append(collection.name)
                }
            }
            collectionScreenshotIDsByUUID = memberships
            collectionNamesByScreenshotID = namesByScreenshotID

            let tagsByScreenshotUUID = try tagRepository.tagsByScreenshotUUID()
            let ocrResults = try ocrRepository.fetchAll()
            ocrResultsByScreenshotUUID = Dictionary(uniqueKeysWithValues: ocrResults.map { ($0.screenshotUUID, $0) })
            for id in orderedIDs {
                screenshotsByID[id]?.tags = tagsByScreenshotUUID[id.uuidString.lowercased()]?.map(\.name) ?? []
                if var screenshot = screenshotsByID[id] {
                    Self.applyOCR(ocrResultsByScreenshotUUID[id.uuidString.lowercased()], to: &screenshot)
                    screenshotsByID[id] = screenshot
                }
            }
            objectWillChange.send()
            if pruneSelection { pruneSelectionToVisible() }
            print("[AppState] organization refresh collections=\(collections.count)")
        } catch {
            print("[AppState] organization refresh failed: \(error)")
        }
    }

    // MARK: - Smart Organization Rules

    func refreshOrganizationRules() {
        do {
            organizationRules = try organizationRuleRepository.fetchAll()
        } catch {
            print("[Rules] refresh failed: \(error)")
        }
    }

    func createOrganizationRule(
        name: String,
        field: RuleConditionField,
        value: String,
        tagName: String,
        collectionName: String?,
        runOnImport: Bool,
        runAfterOCR: Bool
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCollection = collectionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedValue.isEmpty else {
            showToast("Rule name and condition are required", kind: .info)
            return
        }
        var actions: [RuleAction] = []
        if !trimmedTag.isEmpty {
            actions.append(.addTag(name: trimmedTag))
        }
        if let trimmedCollection, !trimmedCollection.isEmpty {
            actions.append(.addToCollection(nameOrUUID: trimmedCollection))
        }
        guard !actions.isEmpty else {
            showToast("Add at least one rule action", kind: .info)
            return
        }
        do {
            let nextPriority = (organizationRules.map(\.priority).max() ?? -1) + 1
            _ = try organizationRuleRepository.create(rule: OrganizationRule(
                name: trimmedName,
                priority: nextPriority,
                conditions: [
                    RuleCondition(field: field, operator: .contains, value: trimmedValue, caseSensitive: false)
                ],
                actions: actions,
                runOnImport: runOnImport,
                runAfterOCR: runAfterOCR
            ))
            refreshOrganizationRules()
            showToast("Created rule \(trimmedName)", kind: .success)
        } catch {
            print("[Rules] create failed: \(error)")
            showToast("Could not create rule", kind: .info)
        }
    }

    func updateOrganizationRule(
        uuid: String,
        name: String,
        field: RuleConditionField,
        value: String,
        tagName: String,
        collectionName: String?,
        runOnImport: Bool,
        runAfterOCR: Bool
    ) {
        guard var rule = organizationRules.first(where: { $0.uuid == uuid }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCollection = collectionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedValue.isEmpty else {
            showToast("Rule name and condition are required", kind: .info)
            return
        }
        var actions: [RuleAction] = []
        if !trimmedTag.isEmpty {
            actions.append(.addTag(name: trimmedTag))
        }
        if let trimmedCollection, !trimmedCollection.isEmpty {
            actions.append(.addToCollection(nameOrUUID: trimmedCollection))
        }
        guard !actions.isEmpty else {
            showToast("Add at least one rule action", kind: .info)
            return
        }
        rule.name = trimmedName
        rule.conditions = [
            RuleCondition(field: field, operator: .contains, value: trimmedValue, caseSensitive: false)
        ]
        rule.actions = actions
        rule.runOnImport = runOnImport
        rule.runAfterOCR = runAfterOCR
        do {
            try organizationRuleRepository.update(rule: rule)
            refreshOrganizationRules()
            showToast("Updated rule \(trimmedName)", kind: .success)
        } catch {
            print("[Rules] update failed: \(error)")
            showToast("Could not update rule", kind: .info)
        }
    }

    func setOrganizationRuleEnabled(_ rule: OrganizationRule, enabled: Bool) {
        do {
            try organizationRuleRepository.setEnabled(uuid: rule.uuid, enabled: enabled)
            refreshOrganizationRules()
        } catch {
            print("[Rules] toggle failed: \(error)")
            showToast("Could not update rule", kind: .info)
        }
    }

    func deleteOrganizationRule(_ rule: OrganizationRule) {
        do {
            try organizationRuleRepository.delete(uuid: rule.uuid)
            refreshOrganizationRules()
            showToast("Deleted rule", kind: .success)
        } catch {
            print("[Rules] delete failed: \(error)")
            showToast("Could not delete rule", kind: .info)
        }
    }

    func runRulesNowForSelection() {
        let ids = selectedScreenshots.map(\.uuidString)
        guard !ids.isEmpty else {
            showToast("Select screenshots before running rules", kind: .info)
            return
        }
        runRulesNow(ids: ids, manual: true)
    }

    func runRulesNowForAllScreenshots() {
        runRulesNow(ids: allScreenshots.filter { !$0.isTrashed }.map(\.uuidString), manual: true)
    }

    private func runRulesAfterImport(_ screenshots: [Screenshot]) {
        runRulesNow(ids: screenshots.map(\.uuidString), trigger: .importComplete, manual: false)
    }

    private func runRulesAfterOCR(screenshotUUID: String) {
        runRulesNow(ids: [screenshotUUID], trigger: .ocrComplete, manual: false)
    }

    private func runRulesAfterCodeDetection(screenshotUUID: String) {
        runRulesNow(ids: [screenshotUUID], trigger: .qrComplete, manual: false)
    }

    private func runRulesNow(ids: [String], trigger: RuleTrigger = .manual, manual: Bool) {
        let normalized = ids.map { $0.lowercased() }
        guard !normalized.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.organizationRuleService.runRules(for: normalized, trigger: trigger)
                await MainActor.run {
                    self.refreshOrganizationState(pruneSelection: false)
                    self.refreshOrganizationRules()
                    self.refreshDuplicateGroups()
                    if manual {
                        self.showToast(Self.ruleRunSummary(result), kind: .success)
                    } else if result.tagsAdded > 0 || result.collectionMembershipsAdded > 0 || result.favoritesChanged > 0 {
                        print("[Rules] auto applied screenshots=\(result.screenshotsChanged) tags=\(result.tagsAdded) collections=\(result.collectionMembershipsAdded) favorites=\(result.favoritesChanged)")
                    }
                }
            } catch {
                await MainActor.run {
                    print("[Rules] run failed: \(error)")
                    if manual {
                        self.showToast("Could not run rules", kind: .info)
                    }
                }
            }
        }
    }

    private static func ruleRunSummary(_ result: BatchRuleEvaluationResult) -> String {
        let actionCount = result.tagsAdded + result.collectionMembershipsAdded + result.favoritesChanged
        guard actionCount > 0 else { return "No rule changes needed" }
        return "Rules applied to \(result.screenshotsChanged) screenshot\(result.screenshotsChanged == 1 ? "" : "s"): \(result.tagsAdded) tag\(result.tagsAdded == 1 ? "" : "s"), \(result.collectionMembershipsAdded) collection membership\(result.collectionMembershipsAdded == 1 ? "" : "s")"
    }

    // MARK: - OCR

    func startOCRQueue() {
        guard database != nil else { return }
        ocrQueueService.start(
            onUpdate: { [weak self] in
                self?.refreshOCRState()
            },
            onComplete: { [weak self] screenshotUUID in
                self?.runRulesAfterOCR(screenshotUUID: screenshotUUID)
            }
        )
    }

    func refreshOCRState() {
        do {
            let results = try ocrRepository.fetchAll()
            ocrResultsByScreenshotUUID = Dictionary(uniqueKeysWithValues: results.map { ($0.screenshotUUID, $0) })
            for id in orderedIDs {
                if var screenshot = screenshotsByID[id] {
                    Self.applyOCR(ocrResultsByScreenshotUUID[id.uuidString.lowercased()], to: &screenshot)
                    screenshotsByID[id] = screenshot
                }
            }
            objectWillChange.send()
            pruneSelectionToVisible()
        } catch {
            print("[OCR] refresh failed: \(error)")
        }
    }

    func ocrResult(for screenshot: Screenshot) -> OCRResult? {
        ocrResultsByScreenshotUUID[screenshot.uuidString]
    }

    func rerunOCR(for shots: [Screenshot]) {
        let valid = shots.filter { $0.libraryPath != nil }
        guard !valid.isEmpty else {
            showToast("No screenshots available for OCR", kind: .info)
            return
        }
        ocrQueueService.rerun(valid)
        showToast(valid.count == 1 ? "Re-running OCR" : "Re-running OCR for \(valid.count) screenshots", kind: .info)
    }

    private static func applyOCR(_ result: OCRResult?, to screenshot: inout Screenshot) {
        guard let result else {
            screenshot.ocrSnippets = []
            screenshot.isOCRComplete = false
            return
        }
        let text = result.text ?? ""
        screenshot.ocrSnippets = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        screenshot.isOCRComplete = result.status == .complete
    }

    // MARK: - Code Detection

    func startCodeDetectionQueue() {
        guard database != nil else { return }
        codeDetectionQueueService.start(
            screenshots: allScreenshots,
            onUpdate: { [weak self] in
                self?.refreshDetectedCodes()
            },
            onComplete: { [weak self] screenshotUUID in
                self?.runRulesAfterCodeDetection(screenshotUUID: screenshotUUID)
            }
        )
    }

    func refreshDetectedCodes() {
        do {
            detectedCodesByScreenshotUUID = Dictionary(
                grouping: try detectedCodeRepository.fetchAll(),
                by: \.screenshotUUID
            )
            objectWillChange.send()
        } catch {
            print("[CodeDetection] refresh failed: \(error)")
        }
    }

    func detectedCodes(for screenshot: Screenshot) -> [DetectedCode] {
        detectedCodesByScreenshotUUID[screenshot.uuidString] ?? []
    }

    func rerunCodeDetection(for shots: [Screenshot]) {
        let valid = shots.filter { $0.libraryPath != nil }
        guard !valid.isEmpty else {
            showToast("No screenshots available for QR detection", kind: .info)
            return
        }
        codeDetectionQueueService.rerun(valid)
        showToast(valid.count == 1 ? "Re-detecting codes" : "Re-detecting codes for \(valid.count) screenshots", kind: .info)
    }

    func copyDetectedCode(_ code: DetectedCode) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code.payload, forType: .string)
        showToast(code.isURL ? "Copied link" : "Copied text", kind: .success)
    }

    func openDetectedCode(_ code: DetectedCode) {
        guard code.isURL,
              let url = URL(string: code.payload.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            showToast("Detected code is not a link", kind: .info)
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Auto Import

    func startAutoImport() {
        guard database != nil else { return }
        autoImportService.start { [weak self] result in
            self?.handleAutoImportResult(result)
        }
        if !isAutoImportEnabled {
            autoImportService.stop()
        }
    }

    func refreshImportSources(reloadWatchers: Bool = true) {
        do {
            importSources = try importSourceRepository.fetchAll()
            if reloadWatchers && isAutoImportEnabled {
                autoImportService.reloadWatchers()
            }
        } catch {
            print("[AppState] import sources refresh failed: \(error)")
            showToast("Could not load watched folders", kind: .info)
        }
    }

    func addImportSource(folderURL: URL) {
        let access = folderAccessService.resolveAccess(for: folderURL)
        let standardized = access.url
        guard !isInsideLibrary(standardized) else {
            showToast("The library folder cannot be watched", kind: .info)
            return
        }
        guard folderAccessService.validateReadableFolder(standardized) else {
            showToast(folderAccessService.accessFailureMessage(for: standardized), kind: .info)
            return
        }
        do {
            if importSources.contains(where: { URL(fileURLWithPath: $0.folderPath).standardizedFileURL.path == standardized.path }) {
                showToast("Folder is already watched", kind: .info)
                return
            }
            _ = try importSourceRepository.create(
                folderPath: standardized.path,
                displayName: standardized.lastPathComponent,
                recursive: false
            )
            refreshImportSources()
            showToast("Added watched folder", kind: .success)
        } catch {
            print("[AppState] add import source failed: \(error)")
            showToast("Could not add watched folder", kind: .info)
        }
    }

    func setImportSourceEnabled(_ source: ImportSource, enabled: Bool) {
        do {
            try importSourceRepository.setEnabled(uuid: source.uuid, enabled: enabled)
            refreshImportSources()
        } catch {
            print("[AppState] import source toggle failed: \(error)")
            showToast("Could not update watched folder", kind: .info)
        }
    }

    func revealLibraryInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([library.libraryRootURL])
    }

    func openPrivacyDocument() {
        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("PRIVACY.md")
        if FileManager.default.fileExists(atPath: localURL.path) {
            NSWorkspace.shared.open(localURL)
            return
        }
        showToast("Privacy document is included as PRIVACY.md in the project repository", kind: .info)
    }

    func resetLayoutPreferences() {
        preferences.inspectorVisibleByDefault = AppPreferences.defaults.inspectorVisibleByDefault
        preferences.sidebarVisibleByDefault = AppPreferences.defaults.sidebarVisibleByDefault
        preferences.preferredAppearance = AppPreferences.defaults.preferredAppearance
        inspectorOverrideVisible = preferences.inspectorVisibleByDefault
        sidebarOverrideVisible = preferences.sidebarVisibleByDefault
        showToast("Layout preferences reset", kind: .success)
    }

    func setOCRLanguagePreset(_ preset: OCRLanguagePreset) {
        preferences.ocrLanguagePreset = preset
        preferences.ocrPreferredLanguages = preset.languages
    }

    func rebuildSearchIndex() {
        maintenanceStatusText = "Search index not required: search uses live local data."
        showToast("Search index not required", kind: .info)
    }

    func runLibraryIntegrityCheck() {
        guard !isMaintenanceRunning else { return }
        isMaintenanceRunning = true
        maintenanceStatusText = "Checking library integrity..."
        let service = libraryIntegrityService
        Task.detached(priority: .utility) {
            do {
                let report = try service.checkIntegrity()
                await MainActor.run {
                    self.libraryIntegrityReport = report
                    self.maintenanceStatusText = report.hasProblems ? "Integrity check finished with issues." : "Library health looks good."
                    self.isMaintenanceRunning = false
                    self.showToast("Library integrity check complete", kind: report.hasProblems ? .info : .success)
                }
            } catch {
                await MainActor.run {
                    print("[Maintenance] integrity check failed: \(error)")
                    self.maintenanceStatusText = "Integrity check failed."
                    self.isMaintenanceRunning = false
                    self.showToast("Could not check library integrity", kind: .info)
                }
            }
        }
    }

    func revealLibraryFolder() {
        do {
            try library.bootstrap()
            try fileActionService.revealInFinder(library.libraryRootURL)
            showToast("Revealed library folder", kind: .success)
        } catch {
            print("[Library] reveal failed: \(error)")
            showToast("Could not reveal library folder", kind: .info)
        }
    }

    func regenerateMissingThumbnails() {
        runMaintenanceTask(startStatus: "Regenerating missing thumbnails...") { service, progress in
            try service.regenerateMissingThumbnails(progress: progress)
        } completion: { [weak self] _ in
            self?.runLibraryIntegrityCheck()
        }
    }

    func rebuildAllThumbnails() {
        runMaintenanceTask(startStatus: "Rebuilding all thumbnails...") { service, progress in
            try service.rebuildAllThumbnails(progress: progress)
        } completion: { [weak self] _ in
            self?.runLibraryIntegrityCheck()
        }
    }

    func createMissingOCRRecords() {
        runMaintenanceTask(startStatus: "Creating missing OCR records...") { service, _ in
            try service.createMissingOCRRecords()
        } completion: { [weak self] _ in
            self?.refreshOCRState()
        }
    }

    func rerunFailedOCR() {
        runMaintenanceTask(startStatus: "Re-queueing failed OCR...") { service, _ in
            try service.resetFailedOCRRecords()
        } completion: { [weak self] _ in
            self?.refreshOCRState()
            self?.ocrQueueService.processPending()
        }
    }

    func resetProcessingOCRRecords() {
        runMaintenanceTask(startStatus: "Resetting interrupted OCR jobs...") { service, _ in
            try service.resetProcessingOCRRecords()
        } completion: { [weak self] _ in
            self?.refreshOCRState()
            self?.ocrQueueService.processPending()
        }
    }

    func cleanOrphanThumbnails() {
        runMaintenanceTask(startStatus: "Cleaning orphan thumbnails...") { service, _ in
            try service.cleanOrphanThumbnails()
        } completion: { [weak self] _ in
            self?.runLibraryIntegrityCheck()
        }
    }

    func cleanOrphanOriginals() {
        runMaintenanceTask(startStatus: "Cleaning orphan originals...") { service, _ in
            try service.cleanOrphanOriginals()
        } completion: { [weak self] _ in
            self?.runLibraryIntegrityCheck()
        }
    }

    func checkDatabaseIntegrity() {
        guard !isMaintenanceRunning else { return }
        isMaintenanceRunning = true
        maintenanceStatusText = "Checking database..."
        let service = libraryIntegrityService
        Task.detached(priority: .utility) {
            do {
                let result = try service.databaseIntegrityCheck()
                await MainActor.run {
                    self.maintenanceStatusText = "Database integrity: \(result)"
                    self.isMaintenanceRunning = false
                    self.showToast(result == "ok" ? "Database integrity ok" : "Database check found issues", kind: result == "ok" ? .success : .info)
                }
            } catch {
                await MainActor.run {
                    print("[Maintenance] database check failed: \(error)")
                    self.maintenanceStatusText = "Database check failed."
                    self.isMaintenanceRunning = false
                    self.showToast("Could not check database", kind: .info)
                }
            }
        }
    }

    func vacuumDatabase() {
        runMaintenanceTask(startStatus: "Vacuuming database...") { service, _ in
            try service.vacuumDatabase()
        }
    }

    func rebuildDuplicateIndexFromMaintenance() {
        maintenanceStatusText = "Rebuilding duplicate index..."
        rebuildDuplicateIndex()
        showToast("Rebuilding duplicate index", kind: .info)
    }

    private func runMaintenanceTask(
        startStatus: String,
        operation: @escaping (LibraryIntegrityService, @escaping (Int, Int) -> Void) throws -> LibraryMaintenanceResult,
        completion: ((LibraryMaintenanceResult) -> Void)? = nil
    ) {
        guard !isMaintenanceRunning else { return }
        isMaintenanceRunning = true
        maintenanceStatusText = startStatus
        let service = libraryIntegrityService
        Task.detached(priority: .utility) {
            do {
                let result = try operation(service) { current, total in
                    Task { @MainActor in
                        self.maintenanceStatusText = "\(startStatus) \(current) / \(total)"
                    }
                }
                await MainActor.run {
                    self.maintenanceStatusText = result.message
                    self.isMaintenanceRunning = false
                    self.showToast(Self.maintenanceSummary(result), kind: .success)
                    completion?(result)
                }
            } catch {
                await MainActor.run {
                    print("[Maintenance] task failed: \(error)")
                    self.maintenanceStatusText = "Maintenance task failed."
                    self.isMaintenanceRunning = false
                    self.showToast("Maintenance task failed", kind: .info)
                }
            }
        }
    }

    private static func maintenanceSummary(_ result: LibraryMaintenanceResult) -> String {
        var message = "\(result.message): \(result.processed)"
        if result.skipped > 0 {
            message += ", skipped \(result.skipped)"
        }
        return message
    }

    func deleteImportSource(_ source: ImportSource) {
        do {
            try importSourceRepository.delete(uuid: source.uuid)
            refreshImportSources()
            showToast("Removed watched folder", kind: .success)
        } catch {
            print("[AppState] import source delete failed: \(error)")
            showToast("Could not remove watched folder", kind: .info)
        }
    }

    func scanWatchedFoldersNow() {
        showToast("Scanning watched folders…", kind: .info)
        autoImportService.scanEnabledSources()
    }

    private func handleAutoImportResult(_ result: AutoImportResult) {
        applyImportResult(result.importResult, selectImported: false)
        refreshImportSources(reloadWatchers: false)
        #if DEBUG
        print("[AutoImport] refresh complete")
        #endif
        let imported = result.importResult.imported.count
        if imported > 0 {
            showToast("Auto-imported \(imported) screenshot\(imported == 1 ? "" : "s")", kind: .success)
        } else if result.importResult.duplicates > 0 {
            showToast("\(result.importResult.duplicates) duplicate\(result.importResult.duplicates == 1 ? "" : "s") skipped", kind: .info)
        } else if !result.importResult.failures.isEmpty {
            showToast("Auto-import failed for \(result.importResult.failures.count) file\(result.importResult.failures.count == 1 ? "" : "s")", kind: .info)
        }
    }

    private func isInsideLibrary(_ url: URL) -> Bool {
        let root = library.libraryRootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    // MARK: - Selection conveniences

    var selectedScreenshotIDs: Set<UUID> { selection.selectedIDs }
    var selectionCount: Int { selection.count }

    /// First visible (in current grid order) selected screenshot.
    var primarySelection: Screenshot? {
        guard !selection.isEmpty else { return nil }
        let visible = filteredScreenshots
        return visible.first(where: { selection.isSelected($0.id) })
    }

    /// All currently selected screenshots in visible order.
    var selectedScreenshots: [Screenshot] {
        let ids = selection.selectedIDs
        return filteredScreenshots.filter { ids.contains($0.id) }
    }

    /// Drop selection entries that aren't in the current filter result.
    /// Call after sidebar / filter / search changes.
    func pruneSelectionToVisible() {
        let before = selection.count
        selection.prune(visible: filteredScreenshots.map(\.id))
        if selection.count != before {
            logSelectionChange(source: "prune")
        }
    }

    // MARK: - Shortcut targets

    /// Cmd-A from anywhere — single entry point for "select all visible".
    func selectAllVisibleScreenshots() {
        let ids = filteredScreenshots.map(\.id)
        print("[AppState] selectAllVisibleScreenshots; visible=\(ids.count); instance=\(ObjectIdentifier(self))")
        selection.selectAll(in: ids)
        print("[SelectionDebug] Cmd+A selected IDs count = \(selection.selectedIDs.count)")
        logSelectionChange(source: "cmdA")
    }

    /// Plain Escape from anywhere — single entry point for "clear selection".
    func clearScreenshotSelection() {
        print("[AppState] clearScreenshotSelection; instance=\(ObjectIdentifier(self))")
        selection.clear()
        logSelectionChange(source: "clear")
    }

    func replaceSelection(with id: UUID, source: String = "mouse") {
        selection.replace(with: id)
        logSelectionChange(source: source)
    }

    func toggleSelection(_ id: UUID, source: String = "cmdClick") {
        selection.toggle(id)
        logSelectionChange(source: source)
    }

    func extendSelection(to id: UUID, in orderedIDs: [UUID], source: String = "shiftClick") {
        selection.extendRange(to: id, in: orderedIDs)
        logSelectionChange(source: source)
    }

    func setSelectedScreenshotIDs(_ ids: Set<UUID>, source: String) {
        selection.setSelectedIDs(ids, source: source)
        logSelectionChange(source: source)
    }

    private func logSelectionChange(source: String) {
        #if DEBUG
        print("[Selection] source=\(source) selectedCount=\(selection.count)")
        #endif
        print("[SelectionDebug] AppState selectedIDs count = \(selection.selectedIDs.count)")
        objectWillChange.send()
    }

    /// Phase 5: Escape priority is overlay-first, selection-second. Returns
    /// `true` if it consumed the keystroke (overlay was open or selection
    /// was non-empty), `false` if there was nothing to clear.
    @discardableResult
    func handleEscape() -> Bool {
        if closeOverlayIfPresent() { return true }
        if !selection.isEmpty {
            clearScreenshotSelection()
            return true
        }
        return false
    }

    /// Used by Escape paths and by the router before opening a new overlay
    /// (so the new sheet doesn't stack on top of a stale one).
    @discardableResult
    func closeOverlayIfPresent() -> Bool {
        if previewedScreenshotID != nil {
            print("[AppState] closing preview overlay")
            closePreview()
            return true
        }
        if ocrTextViewerScreenshotID != nil {
            print("[AppState] closing OCR text viewer")
            ocrTextViewerScreenshotID = nil
            return true
        }
        if renamingScreenshotID != nil {
            print("[AppState] closing rename overlay")
            cancelRename()
            return true
        }
        if isTagEditorPresented {
            cancelTagEditor()
            return true
        }
        if isCollectionPickerPresented {
            cancelCollectionPicker()
            return true
        }
        return false
    }

    /// Convenient predicate for the menu / shortcut layers.
    var hasOverlayPresented: Bool {
        previewedScreenshotID != nil || ocrTextViewerScreenshotID != nil || renamingScreenshotID != nil || isTagEditorPresented || isCollectionPickerPresented
    }

    /// Debug helper for the on-screen DEBUG bar.
    func printSelectionState() {
        print("[AppState] selection state: count=\(selection.count); ids=\(Array(selection.selectedIDs))")
    }

    /// Install the window-level keyDown monitor. Called from
    /// `MainWindowView.onAppear`.
    func installShortcuts() {
        print("[AppState] installShortcuts; instance=\(ObjectIdentifier(self))")
        shortcuts.onSelectAll = { [weak self] in
            print("[Shortcut→AppState] onSelectAll")
            self?.selectAllVisibleScreenshots()
        }
        shortcuts.onClearSelection = { [weak self] in
            print("[Shortcut→AppState] onClearSelection")
            self?.handleEscape()
        }
        shortcuts.onTrash = { [weak self] in
            guard let self else { return }
            print("[Shortcut→AppState] onTrash")
            let shots = self.selectedScreenshots
            guard !shots.isEmpty else { return }
            self.router.handleDeleteKey(shots)
        }
        shortcuts.onPreview = { [weak self] in
            guard let self else { return }
            print("[Shortcut→AppState] onPreview")
            if self.previewedScreenshotID != nil {
                self.closePreview()
                return
            }
            let shots = self.selectedScreenshots
            self.router.quickLook(shots)
        }
        shortcuts.onPreviewPrevious = { [weak self] in
            guard let self, self.previewedScreenshotID != nil else { return false }
            self.previewPrevious()
            return true
        }
        shortcuts.onPreviewNext = { [weak self] in
            guard let self, self.previewedScreenshotID != nil else { return false }
            self.previewNext()
            return true
        }
        shortcuts.onRename = { [weak self] in
            guard let self else { return }
            print("[Shortcut→AppState] onRename")
            guard let shot = self.primarySelection else { return }
            self.router.rename(shot)
        }
        shortcuts.install { NSApp.keyWindow }
    }

    // MARK: - Phase 5 mutation surface

    /// Marks the given IDs as `isTrashed = true`. Selection is pruned so
    /// counts stay honest. Real rows are persisted via the repository; mock
    /// rows mutate in memory only.
    func trash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let undoIDs = ids.filter { screenshotsByID[$0]?.isTrashed == false }
        let now = Date()
        var realIDs: [UUID] = []
        for id in ids {
            screenshotsByID[id]?.isTrashed = true
            screenshotsByID[id]?.trashDate = now
            screenshotsByID[id]?.modifiedAt = now
            if screenshotsByID[id]?.libraryPath != nil {
                realIDs.append(id)
            }
        }
        if !realIDs.isEmpty {
            do {
                try repository.markTrashed(ids: realIDs, trashed: true)
                print("[Repository] moveToTrash success ids=\(realIDs.map(\.uuidString))")
            } catch {
                print("[AppState] trash persist failed: \(error)")
            }
        }
        objectWillChange.send()
        refreshOrganizationState(pruneSelection: false)
        refreshDuplicateGroups()
        pruneSelectionToVisible()
        print("[AppState] refresh counts inbox=\(inboxCount) favorites=\(favoriteCount) trash=\(trashCount)")
        if !isPerformingUndo, !undoIDs.isEmpty {
            registerUndo(title: "Move to Trash") { [weak self] in
                self?.untrash(ids: undoIDs)
            }
        }
    }

    func untrash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let undoIDs = ids.filter { screenshotsByID[$0]?.isTrashed == true }
        let now = Date()
        var realIDs: [UUID] = []
        for id in ids {
            screenshotsByID[id]?.isTrashed = false
            screenshotsByID[id]?.trashDate = nil
            screenshotsByID[id]?.modifiedAt = now
            if screenshotsByID[id]?.libraryPath != nil {
                realIDs.append(id)
            }
        }
        if !realIDs.isEmpty {
            do {
                try repository.restoreFromTrash(ids: realIDs)
            } catch {
                print("[AppState] untrash persist failed: \(error)")
            }
        }
        objectWillChange.send()
        refreshOrganizationState(pruneSelection: false)
        refreshDuplicateGroups()
        rebuildDuplicateHashes(for: screenshots(for: Array(ids)), force: false)
        pruneSelectionToVisible()
        if !isPerformingUndo, !undoIDs.isEmpty {
            registerUndo(title: "Restore from Trash") { [weak self] in
                self?.trash(ids: undoIDs)
            }
        }
    }

    func restoreAllFromTrash() {
        let trashedIDs = allScreenshots.filter(\.isTrashed).map(\.id)
        guard !trashedIDs.isEmpty else {
            showToast("Trash is empty", kind: .info)
            return
        }
        untrash(ids: Set(trashedIDs))
        showToast("Restored \(trashedIDs.count) screenshot\(trashedIDs.count == 1 ? "" : "s")", kind: .success)
    }

    func beginPermanentDelete(ids: [UUID]) {
        let valid = ids.compactMap { screenshotsByID[$0] }.filter(\.isTrashed).map(\.id)
        guard !valid.isEmpty else {
            showToast("No trashed screenshots to delete", kind: .info)
            return
        }
        isEmptyTrashDeletePending = false
        permanentDeleteTargetIDs = valid
    }

    func beginEmptyTrash() {
        let trashedIDs = allScreenshots.filter(\.isTrashed).map(\.id)
        guard !trashedIDs.isEmpty else {
            showToast("Trash is empty", kind: .info)
            return
        }
        isEmptyTrashDeletePending = true
        permanentDeleteTargetIDs = trashedIDs
    }

    func cancelPermanentDelete() {
        isEmptyTrashDeletePending = false
        permanentDeleteTargetIDs = []
    }

    var permanentDeleteTargetCount: Int {
        permanentDeleteTargetIDs.count
    }

    func confirmPermanentDelete() {
        let targets = permanentDeleteTargetIDs.compactMap { screenshotsByID[$0] }.filter(\.isTrashed)
        guard !targets.isEmpty else {
            cancelPermanentDelete()
            return
        }
        let ids = targets.map(\.id)
        do {
            try repository.permanentlyDelete(ids: ids.map { $0.uuidString.lowercased() })
        } catch {
            print("[AppState] permanent delete persist failed: \(error)")
            showToast("Could not delete permanently", kind: .info)
            return
        }
        for screenshot in targets {
            removeManagedFiles(for: screenshot)
        }
        let idSet = Set(ids)
        screenshotsByID = screenshotsByID.filter { !idSet.contains($0.key) }
        orderedIDs.removeAll { idSet.contains($0) }
        selection.prune(visible: filteredScreenshots.map(\.id))
        isEmptyTrashDeletePending = false
        permanentDeleteTargetIDs = []
        refreshOrganizationState(pruneSelection: true)
        refreshDetectedCodes()
        refreshDuplicateGroups()
        objectWillChange.send()
        showToast("Permanently deleted \(targets.count) screenshot\(targets.count == 1 ? "" : "s")", kind: .success)
    }

    var permanentDeleteAlertTitle: String {
        isEmptyTrashDeletePending ? "Empty Trash?" : "Delete Permanently?"
    }

    var permanentDeleteAlertMessage: String {
        let n = permanentDeleteTargetCount
        return "\(n) managed Screenshot Inbox cop\(n == 1 ? "y" : "ies") will be permanently deleted. Original source files outside the managed library are not deleted. This cannot be undone."
    }

    var permanentDeleteConfirmButtonTitle: String {
        isEmptyTrashDeletePending ? "Empty Trash" : "Delete"
    }

    private func removeManagedFiles(for screenshot: Screenshot) {
        let fileManager = FileManager.default
        var urls: [URL] = [
            library.smallThumbnailURL(for: screenshot.id),
            library.largeThumbnailURL(for: screenshot.id)
        ]
        if let libraryPath = screenshot.libraryPath, !libraryPath.isEmpty {
            let originalURL = libraryPath.hasPrefix("/")
                ? URL(fileURLWithPath: libraryPath)
                : library.libraryRootURL.appendingPathComponent(libraryPath)
            if isManagedLibraryURL(originalURL) {
                urls.append(originalURL)
            } else {
                #if DEBUG
                print("[AppState] skip deleting non-library original path=\(originalURL.path)")
                #endif
            }
        }
        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                #if DEBUG
                print("[AppState] managed file delete failed path=\(url.path) error=\(error)")
                #endif
            }
        }
    }

    private func isManagedLibraryURL(_ url: URL) -> Bool {
        let rootPath = library.libraryRootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    var undoMenuTitle: String {
        appUndoService.nextUndoTitle
    }

    func performAppUndo() {
        appUndoService.undoLast()
    }

    private func registerUndo(title: String, undo: @escaping () -> Void) {
        appUndoService.push(title: title, undo: undo)
        pendingToastUndoTitle = "Undo"
    }

    private func performUndoMutation(_ mutation: () -> Void) {
        let wasPerformingUndo = isPerformingUndo
        isPerformingUndo = true
        mutation()
        isPerformingUndo = wasPerformingUndo
    }

    private func removeTagForUndo(uuid tagUUID: String, from ids: [UUID]) {
        performUndoMutation {
            let screenshotUUIDs = ids.map { $0.uuidString.lowercased() }
            do {
                try tagRepository.removeTag(tagUUID: tagUUID, fromScreenshots: screenshotUUIDs)
                refreshOrganizationState(pruneSelection: false)
                showToast("Undid Add Tag", kind: .success)
            } catch {
                print("[Undo] remove tag failed: \(error)")
                showToast("Could not undo Add Tag", kind: .info)
            }
        }
    }

    private func removeScreenshotsFromCollectionForUndo(ids: [UUID], collectionUUID: String) {
        performUndoMutation {
            let screenshotUUIDs = ids.map { $0.uuidString.lowercased() }
            do {
                try collectionRepository.removeScreenshots(screenshotUUIDs, fromCollection: collectionUUID)
                refreshOrganizationState(pruneSelection: false)
                showToast("Undid Add to Collection", kind: .success)
            } catch {
                print("[Undo] remove from collection failed: \(error)")
                showToast("Could not undo Add to Collection", kind: .info)
            }
        }
    }

    private func restoreFavoriteStates(_ previous: [UUID: Bool]) {
        performUndoMutation {
            for (id, isFavorite) in previous {
                setFavorite(ids: [id], isFavorite: isFavorite)
            }
            showToast("Undid Favorite", kind: .success)
        }
    }

    private func restoreRenamedScreenshot(_ previous: Screenshot) {
        performUndoMutation {
            do {
                if let current = screenshotsByID[previous.id],
                   current.libraryPath != previous.libraryPath,
                   let currentPath = current.libraryPath,
                   let previousPath = previous.libraryPath {
                    let currentURL = library.libraryRootURL.appendingPathComponent(currentPath)
                    let previousURL = library.libraryRootURL.appendingPathComponent(previousPath)
                    if FileManager.default.fileExists(atPath: currentURL.path),
                       !FileManager.default.fileExists(atPath: previousURL.path) {
                        try FileManager.default.moveItem(at: currentURL, to: previousURL)
                    }
                }
                screenshotsByID[previous.id] = previous
                if previous.libraryPath != nil {
                    try repository.update(previous)
                }
                objectWillChange.send()
                showToast("Undid Rename", kind: .success)
            } catch {
                print("[Undo] rename restore failed: \(error)")
                showToast("Could not undo Rename", kind: .info)
            }
        }
    }

    func setFavorite(ids: Set<UUID>, isFavorite: Bool) {
        guard !ids.isEmpty else { return }
        let previous = Dictionary(uniqueKeysWithValues: ids.compactMap { id -> (UUID, Bool)? in
            guard let screenshot = screenshotsByID[id], screenshot.isFavorite != isFavorite else { return nil }
            return (id, screenshot.isFavorite)
        })
        let now = Date()
        var realIDs: [UUID] = []
        for id in ids {
            screenshotsByID[id]?.isFavorite = isFavorite
            screenshotsByID[id]?.modifiedAt = now
            if screenshotsByID[id]?.libraryPath != nil {
                realIDs.append(id)
            }
        }
        if !realIDs.isEmpty {
            do {
                try repository.updateFavorite(ids: realIDs, isFavorite: isFavorite)
                print("[Repository] updateFavorite success favorite=\(isFavorite) ids=\(realIDs.map(\.uuidString))")
            } catch {
                print("[AppState] favorite persist failed: \(error)")
            }
        }
        objectWillChange.send()
        pruneSelectionToVisible()
        print("[AppState] refresh counts inbox=\(inboxCount) favorites=\(favoriteCount) trash=\(trashCount)")
        if !isPerformingUndo, !previous.isEmpty {
            registerUndo(title: isFavorite ? "Favorite" : "Unfavorite") { [weak self] in
                self?.restoreFavoriteStates(previous)
            }
        }
    }

    private func nextCollectionName() -> String {
        let existing = Set(collections.map(\.name))
        let base = "New Collection"
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    // MARK: - Import

    /// Run an import batch and merge the new rows into the in-memory store.
    /// Falls back gracefully if the persistence stack failed to bootstrap —
    /// the user just sees an error toast.
    func importURLs(_ urls: [URL]) async {
        await importURLs(urls, unsupportedCount: 0, selectImported: false)
    }

    func importDroppedFileURLs(_ urls: [URL], unsupportedCount: Int) async {
        let supported = urls.filter(DragDropController.isSupportedImageURL)
        let ignored = unsupportedCount + urls.count - supported.count
        await importURLs(supported, unsupportedCount: ignored, selectImported: true)
    }

    private func importURLs(
        _ urls: [URL],
        unsupportedCount: Int,
        selectImported: Bool
    ) async {
        guard !urls.isEmpty else {
            if unsupportedCount > 0 {
                showToast(Self.unsupportedMessage(count: unsupportedCount), kind: .info)
            }
            return
        }
        guard database != nil else {
            showToast("Library unavailable — cannot import", kind: .info)
            return
        }
        showToast("Importing \(urls.count)…", kind: .info)
        let result = await importService.importURLs(urls, conflictResolver: MacImportConflictResolver())

        applyImportResult(result, selectImported: selectImported)

        if !result.imported.isEmpty || !result.replaced.isEmpty || result.keptDuplicateCopies > 0 {
            showToast(Self.importSummary(
                imported: result.imported.count,
                duplicates: result.duplicates,
                keptDuplicateCopies: result.keptDuplicateCopies,
                replaced: result.replaced.count,
                unsupported: unsupportedCount,
                failures: result.failures.count
            ), kind: .success)
        } else if result.duplicates > 0 && result.failures.isEmpty && unsupportedCount == 0 {
            showToast(Self.duplicateMessage(count: result.duplicates), kind: .info)
        } else if result.duplicates > 0 || unsupportedCount > 0 {
            showToast(Self.importSummary(
                imported: 0,
                duplicates: result.duplicates,
                keptDuplicateCopies: 0,
                replaced: 0,
                unsupported: unsupportedCount,
                failures: result.failures.count
            ), kind: .info)
        } else if !result.failures.isEmpty {
            showToast("Import failed for \(result.failures.count) file\(result.failures.count == 1 ? "" : "s")", kind: .info)
        }
    }

    private func applyImportResult(_ result: ImportResult, selectImported: Bool) {
        // First successful import flushes the mock placeholder rows so the
        // grid stops mixing real + mock data.
        if isUsingMockData && !result.imported.isEmpty {
            orderedIDs.removeAll()
            screenshotsByID.removeAll()
            isUsingMockData = false
        }
        // Newest-first: prepend imports in reverse arrival order.
        for shot in result.imported.reversed() {
            orderedIDs.insert(shot.id, at: 0)
            screenshotsByID[shot.id] = shot
        }
        for shot in result.replaced {
            screenshotsByID[shot.id] = shot
        }
        if !result.imported.isEmpty {
            ocrQueueService.enqueue(result.imported)
            codeDetectionQueueService.enqueue(result.imported)
            rebuildDuplicateHashes(for: result.imported)
            runRulesAfterImport(result.imported)
        }
        if !result.replaced.isEmpty {
            ocrQueueService.rerun(result.replaced)
            codeDetectionQueueService.rerun(result.replaced)
            rebuildDuplicateHashes(for: result.replaced, force: true)
            runRulesAfterImport(result.replaced)
        }
        objectWillChange.send()
        refreshOrganizationState(pruneSelection: false)
        refreshDuplicateGroups()

        if selectImported {
            let importedIDs = Set(result.imported.map(\.id))
            let visibleImportedIDs = filteredScreenshots
                .map(\.id)
                .filter { importedIDs.contains($0) }
            if !visibleImportedIDs.isEmpty {
                selection.selectAll(in: visibleImportedIDs)
                logSelectionChange(source: "import")
            }
        }
    }

    func copySelectedScreenshotsToPasteboard() {
        let ids = selectedScreenshots.map(\.uuidString)
        guard !ids.isEmpty else {
            showToast("No screenshots selected", kind: .info)
            return
        }
        do {
            let count = try clipboardService.copyScreenshots(ids: ids)
            showToast("Copied \(count) screenshot\(count == 1 ? "" : "s")", kind: .success)
        } catch {
            print("[Clipboard] copy failed: \(error)")
            showToast(error.localizedDescription, kind: .info)
        }
    }

    func pasteClipboardIntoInbox() {
        Task { [weak self] in
            guard let self else { return }
            guard database != nil else {
                showToast("Library unavailable — cannot import", kind: .info)
                return
            }
            guard clipboardService.canPasteImageContent() else {
                showToast("No image found on clipboard", kind: .info)
                return
            }
            do {
                showToast("Importing clipboard image…", kind: .info)
                let result = try await clipboardService.pasteIntoInbox()
                applyImportResult(result, selectImported: true)
                if !result.imported.isEmpty || !result.replaced.isEmpty || result.keptDuplicateCopies > 0 {
                    showToast(Self.importSummary(
                        imported: result.imported.count,
                        duplicates: result.duplicates,
                        keptDuplicateCopies: result.keptDuplicateCopies,
                        replaced: result.replaced.count,
                        unsupported: 0,
                        failures: result.failures.count
                    ), kind: .success)
                } else if result.duplicates > 0 {
                    showToast(Self.duplicateMessage(count: result.duplicates), kind: .info)
                } else if !result.failures.isEmpty {
                    showToast("Import failed for \(result.failures.count) file\(result.failures.count == 1 ? "" : "s")", kind: .info)
                } else {
                    showToast("No screenshots imported", kind: .info)
                }
            } catch ScreenshotClipboardError.noImageContent {
                showToast("No image found on clipboard", kind: .info)
            } catch {
                print("[Clipboard] paste failed: \(error)")
                showToast(error.localizedDescription, kind: .info)
            }
        }
    }

    func cutSelectedScreenshotsToPasteboard() {
        let ids = selectedScreenshots.map(\.uuidString)
        guard !ids.isEmpty else { return }
        do {
            try clipboardService.cutScreenshots(ids: ids)
        } catch {
            showToast("Cut is not available for screenshots", kind: .info)
        }
    }

    private static func importSummary(
        imported: Int,
        duplicates: Int,
        keptDuplicateCopies: Int,
        replaced: Int,
        unsupported: Int,
        failures: Int
    ) -> String {
        var parts: [String] = []
        if imported > 0 {
            parts.append("Imported \(imported) screenshot\(imported == 1 ? "" : "s")")
        }
        if duplicates > 0 {
            parts.append("skipped \(duplicates) duplicate\(duplicates == 1 ? "" : "s")")
        }
        if keptDuplicateCopies > 0 {
            parts.append("kept \(keptDuplicateCopies) duplicate cop\(keptDuplicateCopies == 1 ? "y" : "ies")")
        }
        if replaced > 0 {
            parts.append("replaced \(replaced) screenshot\(replaced == 1 ? "" : "s")")
        }
        if unsupported > 0 {
            parts.append("\(unsupported) unsupported file\(unsupported == 1 ? "" : "s") ignored")
        }
        if failures > 0 {
            parts.append("\(failures) failed")
        }
        return parts.isEmpty ? "No screenshots imported" : parts.joined(separator: ", ")
    }

    private static func duplicateMessage(count: Int) -> String {
        "Skipped \(count) duplicate\(count == 1 ? "" : "s")"
    }

    private static func unsupportedMessage(count: Int) -> String {
        "\(count) unsupported file\(count == 1 ? "" : "s") ignored"
    }

    // MARK: - Duplicate index

    private static func makeDuplicateGroups(
        screenshots: [Screenshot],
        imageHashes: [String: ImageHashRecord]
    ) -> [DuplicateGroup] {
        DuplicateDetectionService.findDuplicateGroups(
            screenshots: screenshots,
            imageHashes: imageHashes,
            includeTrashed: false
        )
    }

    private func refreshDuplicateGroups() {
        duplicateGroups = Self.makeDuplicateGroups(
            screenshots: allScreenshots,
            imageHashes: imageHashesByScreenshotUUID
        )
        #if DEBUG
        print("[Duplicates] groups=\(duplicateGroups.count) duplicateItems=\(duplicatesCount)")
        #endif
    }

    func printDuplicateGroups() {
        refreshDuplicateGroups()
        if duplicateGroups.isEmpty {
            print("[Duplicates] no groups")
            return
        }
        for group in duplicateGroups {
            print("[Duplicates] \(group.kind.rawValue) count=\(group.screenshotUUIDs.count) keep=\(group.recommendedKeepUUID ?? "nil") ids=\(group.screenshotUUIDs)")
        }
    }

    func rebuildDuplicateIndex() {
        rebuildDuplicateHashes(for: allScreenshots.filter { !$0.isTrashed }, force: true)
    }

    private func rebuildMissingDuplicateHashes() {
        let missing = allScreenshots.filter {
            !$0.isTrashed && imageHashesByScreenshotUUID[$0.uuidString] == nil
        }
        rebuildDuplicateHashes(for: missing, force: false)
    }

    private func rebuildDuplicateHashes(for screenshots: [Screenshot], force: Bool = false) {
        let targets = screenshots.filter { shot in
            guard !shot.isTrashed else { return false }
            return force || imageHashesByScreenshotUUID[shot.uuidString] == nil
        }
        guard !targets.isEmpty else {
            refreshDuplicateGroups()
            maintenanceStatusText = "Duplicate index already up to date."
            return
        }
        let repository = imageHashRepository
        let hasher = imageHashingService
        let libraryRootURL = library.libraryRootURL
        let workItems: [(uuid: String, sourceURL: URL)] = targets.compactMap { shot in
            guard let sourceURL = Self.hashSourceURL(for: shot, libraryRootURL: libraryRootURL) else {
                return nil
            }
            return (shot.uuidString, sourceURL)
        }
        guard !workItems.isEmpty else {
            refreshDuplicateGroups()
            maintenanceStatusText = "No source images available for duplicate hashing."
            return
        }
        Task.detached(priority: .utility) {
            var records: [ImageHashRecord] = []
            for item in workItems {
                do {
                    let raw = try hasher.hashImage(at: item.sourceURL)
                    let record = ImageHashRecord(
                        screenshotUUID: item.uuid,
                        algorithm: raw.algorithm,
                        hash: raw.hash,
                        createdAt: raw.createdAt
                    )
                    try repository.upsert(record)
                    records.append(record)
                } catch {
                    print("[Duplicates] hash failed uuid=\(item.uuid) error=\(error)")
                }
            }
            let completedRecords = records
            await MainActor.run {
                for record in completedRecords {
                    self.imageHashesByScreenshotUUID[record.screenshotUUID] = record
                }
                self.refreshDuplicateGroups()
                self.maintenanceStatusText = "Duplicate index rebuilt."
                #if DEBUG
                print("[Duplicates] hash rebuild complete records=\(completedRecords.count)")
                #endif
            }
        }
    }

    private static func hashSourceURL(for screenshot: Screenshot, libraryRootURL: URL) -> URL? {
        if let uuid = UUID(uuidString: screenshot.uuidString) {
            let large = libraryRootURL
                .appendingPathComponent("Thumbnails")
                .appendingPathComponent("large")
                .appendingPathComponent("\(uuid.uuidString.lowercased()).jpg")
            if FileManager.default.fileExists(atPath: large.path) {
                return large
            }
        }
        guard let path = screenshot.libraryPath, !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return libraryRootURL.appendingPathComponent(path)
    }

    // MARK: - PDF Export

    func beginPDFExport(_ shots: [Screenshot]) {
        guard !shots.isEmpty else {
            showToast("Select screenshots to export", kind: .info)
            return
        }
        pdfExportTargetIDs = shots.map(\.id)
        pdfExportOptions = .defaults(outputPath: defaultPDFExportPath())
        isPDFExportSheetPresented = true
    }

    func cancelPDFExport() {
        guard !isPDFExporting else { return }
        isPDFExportSheetPresented = false
        pdfExportTargetIDs = []
    }

    func exportPDF() async {
        guard !isPDFExporting else { return }
        let shots = screenshots(for: pdfExportTargetIDs)
        guard !shots.isEmpty else {
            showToast("Select screenshots to export", kind: .info)
            return
        }
        var options = pdfExportOptions
        if !options.outputPath.lowercased().hasSuffix(".pdf") {
            options.outputPath += ".pdf"
            pdfExportOptions = options
        }
        isPDFExporting = true
        do {
            let result = try await pdfExportService.export(screenshots: shots, options: options)
            isPDFExporting = false
            isPDFExportSheetPresented = false
            pdfExportTargetIDs = []
            var message = "Exported PDF"
            if result.skippedCount > 0 {
                message += " (\(result.skippedCount) skipped)"
            }
            showToast(message, kind: .success)
        } catch PDFExportError.noRenderableImages {
            isPDFExporting = false
            showToast("No source images found", kind: .info)
        } catch {
            isPDFExporting = false
            print("[PDFExport] failed: \(error)")
            showToast("Could not export PDF", kind: .info)
        }
    }

    var pdfExportTargetCount: Int {
        pdfExportTargetIDs.count
    }

    private func defaultPDFExportPath() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "Screenshot Export \(formatter.string(from: Date())).pdf"
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let folder = downloads ?? library.libraryRootURL.appendingPathComponent("Exports/PDFs", isDirectory: true)
        return uniqueExportURL(in: folder, filename: filename).path
    }

    private func uniqueExportURL(in folder: URL, filename: String) -> URL {
        let fileManager = FileManager.default
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        func candidate(_ suffix: Int?) -> URL {
            let stem = suffix.map { "\(base) \($0)" } ?? base
            let name = ext.isEmpty ? stem : "\(stem).\(ext)"
            return folder.appendingPathComponent(name)
        }
        var url = candidate(nil)
        guard fileManager.fileExists(atPath: url.path) else { return url }
        var index = 2
        repeat {
            url = candidate(index)
            index += 1
        } while fileManager.fileExists(atPath: url.path)
        return url
    }

    // MARK: - Export / Share

    func exportOriginals(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { return }
        guard let folder = chooseExportFolder(message: "Choose a folder for exported originals") else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.exportShareService.exportOriginals(shots, to: folder)
                await MainActor.run {
                    var message = "Exported \(result.exportedCount) screenshot\(result.exportedCount == 1 ? "" : "s")"
                    if result.skippedCount > 0 {
                        message += ", skipped \(result.skippedCount) missing file\(result.skippedCount == 1 ? "" : "s")"
                    }
                    self.showToast(message, kind: .success)
                }
            } catch {
                await MainActor.run {
                    print("[Export] originals failed: \(error)")
                    self.showToast("Could not export originals", kind: .info)
                }
            }
        }
    }

    func exportCurrentCollection() {
        guard case .collection(let uuid)? = sidebarSelection else {
            showToast("Select a collection first", kind: .info)
            return
        }
        let ids = collectionScreenshotIDsByUUID[uuid] ?? []
        let shots = allScreenshots.filter { ids.contains($0.id) && !$0.isTrashed }
        guard !shots.isEmpty else {
            showToast("Collection is empty", kind: .info)
            return
        }
        exportOriginals(shots)
    }

    func exportOCRText(_ shots: [Screenshot], format: OCRTextExportFormat) {
        guard !shots.isEmpty else { return }
        let ext = format == .markdown ? "md" : "txt"
        guard let outputURL = chooseExportFile(
            title: format == .markdown ? "Export OCR Markdown" : "Export OCR Text",
            filename: "Screenshot OCR Export.\(ext)"
        ) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.exportShareService.exportOCRText(shots, to: outputURL, format: format)
                await MainActor.run {
                    var message = "Exported OCR from \(result.exportedCount) screenshot\(result.exportedCount == 1 ? "" : "s")"
                    if result.skippedCount > 0 {
                        message += ", skipped \(result.skippedCount) without OCR"
                    }
                    self.showToast(message, kind: .success)
                }
            } catch {
                await MainActor.run {
                    print("[Export] OCR failed: \(error)")
                    self.showToast("Could not export OCR text", kind: .info)
                }
            }
        }
    }

    func shareFiles(_ shots: [Screenshot]) {
        let shared = exportShareService.share(shots)
        guard shared > 0 else {
            showToast("No image files available to share", kind: .info)
            return
        }
        if shared < shots.count {
            showToast("Sharing \(shared) file\(shared == 1 ? "" : "s"); skipped \(shots.count - shared) missing file\(shots.count - shared == 1 ? "" : "s")", kind: .info)
        }
    }

    private func chooseExportFolder(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = message
        return panel.runModal() == .OK ? panel.urls.first : nil
    }

    private func chooseExportFile(title: String, filename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Preview overlay

    func beginPreview(of shot: Screenshot) {
        beginPreview(startingAt: shot, navigationShots: nil)
    }

    func beginPreview(startingAt shot: Screenshot, navigationShots: [Screenshot]?) {
        if renamingScreenshotID != nil { cancelRename() }
        let sequence = navigationShots?.map(\.id) ?? filteredScreenshots.map(\.id)
        previewSequenceIDs = sequence.contains(shot.id) ? sequence : [shot.id] + sequence
        previewedScreenshotID = shot.id
    }

    /// Resolves the currently previewed screenshot.
    var previewedScreenshot: Screenshot? {
        guard let id = previewedScreenshotID else { return nil }
        return screenshotsByID[id]
    }

    var previewIndexText: String {
        guard let id = previewedScreenshotID,
              let index = previewSequenceIDs.firstIndex(of: id),
              !previewSequenceIDs.isEmpty else {
            return ""
        }
        return "\(index + 1) of \(previewSequenceIDs.count)"
    }

    var canPreviewPrevious: Bool {
        guard let id = previewedScreenshotID,
              let index = previewSequenceIDs.firstIndex(of: id) else { return false }
        return index > 0
    }

    var canPreviewNext: Bool {
        guard let id = previewedScreenshotID,
              let index = previewSequenceIDs.firstIndex(of: id) else { return false }
        return index < previewSequenceIDs.count - 1
    }

    func previewPrevious() {
        guard let id = previewedScreenshotID,
              let index = previewSequenceIDs.firstIndex(of: id),
              index > 0 else { return }
        previewedScreenshotID = previewSequenceIDs[index - 1]
    }

    func previewNext() {
        guard let id = previewedScreenshotID,
              let index = previewSequenceIDs.firstIndex(of: id),
              index < previewSequenceIDs.count - 1 else { return }
        previewedScreenshotID = previewSequenceIDs[index + 1]
    }

    func closePreview() {
        previewedScreenshotID = nil
        previewSequenceIDs = []
    }

    func advancePreviewAfterRemovingCurrent() {
        guard let id = previewedScreenshotID else { return }
        let oldIndex = previewSequenceIDs.firstIndex(of: id) ?? 0
        previewSequenceIDs.removeAll { removedID in
            removedID == id || screenshotsByID[removedID]?.isTrashed == true
        }
        guard !previewSequenceIDs.isEmpty else {
            closePreview()
            return
        }
        let nextIndex = min(oldIndex, previewSequenceIDs.count - 1)
        previewedScreenshotID = previewSequenceIDs[nextIndex]
    }

    // MARK: - OCR text viewer

    func beginOCRTextViewer(for shot: Screenshot) {
        guard shot.isOCRComplete, !shot.ocrSnippets.isEmpty else {
            showToast("OCR text is not available yet", kind: .info)
            return
        }
        if previewedScreenshotID != nil { previewedScreenshotID = nil }
        if renamingScreenshotID != nil { cancelRename() }
        ocrTextViewerScreenshotID = shot.id
    }

    var ocrTextViewerScreenshot: Screenshot? {
        guard let id = ocrTextViewerScreenshotID else { return nil }
        return screenshotsByID[id]
    }

    // MARK: - Rename overlay

    func beginRename(_ shot: Screenshot) {
        if previewedScreenshotID != nil { previewedScreenshotID = nil }
        renamingScreenshotID = shot.id
        pendingRenameText = shot.name
    }

    func cancelRename() {
        renamingScreenshotID = nil
        pendingRenameText = ""
    }

    func commitRename() {
        guard let id = renamingScreenshotID else { return }
        let trimmed = pendingRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var updated = screenshotsByID[id] else { return }
        let previous = updated
        #if DEBUG
        print("[Rename] requested uuid=\(id.uuidString.lowercased()) newName=\(trimmed)")
        #endif
        do {
            if updated.libraryPath != nil {
                let oldLibraryPath = updated.libraryPath
                updated = try renamedManagedCopy(updated, requestedName: trimmed)
                do {
                    try repository.update(updated)
                } catch {
                    rollbackManagedRenameIfNeeded(from: updated.libraryPath, to: oldLibraryPath)
                    throw error
                }
                #if DEBUG
                print("[Rename] repository updated")
                #endif
            } else {
                updated.name = trimmed
                updated.modifiedAt = Date()
            }
            screenshotsByID[id] = updated
            objectWillChange.send()
            if !isPerformingUndo, previous.name != updated.name || previous.libraryPath != updated.libraryPath {
                registerUndo(title: "Rename") { [weak self] in
                    self?.restoreRenamedScreenshot(previous)
                }
            }
            #if DEBUG
            print("[Rename] AppState updated")
            print("[Rename] inspector selected filename=\(primarySelection?.name ?? "nil")")
            #endif
            showToast("Renamed", kind: .success)
        } catch RenameError.managedFileMissing {
            showToast("Managed file not found", kind: .info)
        } catch {
            print("[AppState] rename persist failed: \(error)")
            showToast("Rename failed", kind: .info)
        }
        cancelRename()
    }

    private func renamedManagedCopy(_ shot: Screenshot, requestedName: String) throws -> Screenshot {
        guard let libraryPath = shot.libraryPath else { return shot }
        let sourceURL = library.libraryRootURL.appendingPathComponent(libraryPath)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw RenameError.managedFileMissing
        }
        let ext = sourceURL.pathExtension
        let baseName = sanitizedFileBaseName(from: requestedName, fallback: sourceURL.deletingPathExtension().lastPathComponent)
        let targetURL = uniqueManagedRenameURL(
            directory: sourceURL.deletingLastPathComponent(),
            baseName: baseName,
            extension: ext,
            originalURL: sourceURL
        )
        var updated = shot
        if targetURL != sourceURL {
            try fileManager.moveItem(at: sourceURL, to: targetURL)
            updated.libraryPath = libraryRelativePath(for: targetURL)
        }
        updated.name = targetURL.lastPathComponent
        updated.modifiedAt = Date()
        return updated
    }

    private func sanitizedFileBaseName(from name: String, fallback: String) -> String {
        let withoutExtension = (name as NSString).deletingPathExtension
        let invalid = CharacterSet(charactersIn: "/:")
        let sanitized = withoutExtension
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
    }

    private func uniqueManagedRenameURL(
        directory: URL,
        baseName: String,
        extension ext: String,
        originalURL: URL
    ) -> URL {
        let fileManager = FileManager.default
        func candidate(_ suffix: Int?) -> URL {
            let stem = suffix.map { "\(baseName) \($0)" } ?? baseName
            let filename = ext.isEmpty ? stem : "\(stem).\(ext)"
            return directory.appendingPathComponent(filename)
        }
        var url = candidate(nil)
        if url == originalURL || !fileManager.fileExists(atPath: url.path) { return url }
        var index = 2
        repeat {
            url = candidate(index)
            index += 1
        } while url != originalURL && fileManager.fileExists(atPath: url.path)
        return url
    }

    private func libraryRelativePath(for url: URL) -> String {
        let rootPath = library.libraryRootURL.path
        let absolute = url.path
        if absolute.hasPrefix(rootPath) {
            var trimmed = String(absolute.dropFirst(rootPath.count))
            if trimmed.hasPrefix("/") { trimmed.removeFirst() }
            return trimmed
        }
        return absolute
    }

    private func rollbackManagedRenameIfNeeded(from newPath: String?, to oldPath: String?) {
        guard let newPath, let oldPath, newPath != oldPath else { return }
        let newURL = library.libraryRootURL.appendingPathComponent(newPath)
        let oldURL = library.libraryRootURL.appendingPathComponent(oldPath)
        guard FileManager.default.fileExists(atPath: newURL.path),
              !FileManager.default.fileExists(atPath: oldURL.path) else { return }
        do {
            try FileManager.default.moveItem(at: newURL, to: oldURL)
        } catch {
            print("[Rename] rollback failed: \(error)")
        }
    }

    /// Resolves the currently renaming screenshot.
    var renamingScreenshot: Screenshot? {
        guard let id = renamingScreenshotID else { return nil }
        return screenshotsByID[id]
    }

    // MARK: - Toast banner

    /// Show a transient banner in the bottom-trailing corner of the window.
    /// Replaces any existing toast and auto-dismisses after ~2.4s.
    func showToast(_ text: String, kind: ToastMessage.Kind = .info, undoTitle: String? = nil) {
        let resolvedUndoTitle = undoTitle ?? pendingToastUndoTitle
        pendingToastUndoTitle = nil
        toast = ToastMessage(text: text, kind: kind, undoTitle: resolvedUndoTitle)
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

/// Lightweight banner payload. Kind drives icon + accent in the toast view.
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: Kind
    let undoTitle: String?

    enum Kind {
        case info
        case success
        case comingSoon
    }
}

private enum RenameError: Error {
    case managedFileMissing
}
