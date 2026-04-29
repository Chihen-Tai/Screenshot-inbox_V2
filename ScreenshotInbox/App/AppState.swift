import Foundation
import Combine
import AppKit

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
    /// Mock rename sheet is shown when this is non-nil.
    @Published var renamingScreenshotID: UUID?
    /// Live rename text-field value. Bound by the rename sheet.
    @Published var pendingRenameText: String = ""
    @Published var tagEditorTargetIDs: [UUID] = []
    @Published var pendingTagText: String = ""
    @Published var isTagEditorPresented: Bool = false
    @Published var collectionPickerTargetIDs: [UUID] = []
    @Published var isCollectionPickerPresented: Bool = false
    /// Currently displayed toast / banner. Auto-clears after a short delay.
    @Published var toast: ToastMessage?

    // MARK: - Selection / shortcuts

    let selection: SelectionController
    let shortcuts = WindowShortcutController()

    /// Phase 5 router. Set in `init` after self is fully constructed so it
    /// can hold an `unowned` ref back without ordering trouble.
    private(set) var router: ScreenshotActionRouter!

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
    private(set) var settingsService: SettingsService
    private(set) var importService: ImportService
    private(set) var autoImportService: AutoImportService
    private(set) var ocrQueueService: OCRQueueService
    private(set) var codeDetectionQueueService: CodeDetectionQueueService
    private(set) var searchService: SearchService
    private(set) var pdfExportService: PDFExporting
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
            print("[AutoImport] development default source added: \(path)")
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
        var loaded: [Screenshot] = []
        var loadedCollections: [ScreenshotCollection] = []
        var loadedCollectionCounts: [String: Int] = [:]
        var loadedCollectionMemberships: [String: Set<UUID>] = [:]
        var loadedTagsByScreenshotUUID: [String: [Tag]] = [:]
        var loadedImportSources: [ImportSource] = []
        var loadedOCRResults: [String: OCRResult] = [:]
        var loadedDetectedCodes: [String: [DetectedCode]] = [:]

        do {
            try library.bootstrap()
            let db = try Database(path: library.databaseURL.path)
            let migrations = MigrationManager()
            migrations.register(.initialSchema)
            migrations.register(.organizationSchema)
            migrations.register(.autoImportSchema)
            migrations.register(.ocrSchema)
            migrations.register(.detectedCodesSchema)
            try migrations.runPending(on: db)

            let repo = ScreenshotRepository(database: db)
            let collectionsRepo = CollectionRepository(database: db)
            let tagsRepo = TagRepository(database: db)
            let importSourcesRepo = ImportSourceRepository(database: db)
            let ocrRepo = OCRRepository(database: db)
            let codesRepo = DetectedCodeRepository(database: db)
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
            print("[AppState] persistence ok: rows=\(loaded.count) at \(library.databaseURL.path)")
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
        self.searchService = SearchService()
        self.pdfExportService = MacPDFExportService(library: library)
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

        let controller = SelectionController()
        self.selection = controller

        // Forward selection changes so anyone observing AppState updates too.
        self.selectionForwarder = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        self.router = ScreenshotActionRouter(appState: self)

        // Pre-seed one item so the inspector populates on launch.
        if let first = allScreenshots.first {
            controller.replace(with: first.id)
        }
        print("[AppState] init instance:", ObjectIdentifier(self), "mock=\(isUsingMockData)")
        startAutoImport()
        startOCRQueue()
        startCodeDetectionQueue()
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
        let nonTrashed = allScreenshots.filter { !$0.isTrashed }
        let base: [Screenshot]
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
            base = []
        case .smart(.thisWeek):
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            base = nonTrashed.filter { $0.createdAt > cutoff }
        }

        let chipFiltered: [Screenshot]
        switch activeFilterChip {
        case .all:         chipFiltered = base
        case .favorites:   chipFiltered = base.filter(\.isFavorite)
        case .ocrComplete: chipFiltered = base.filter(\.isOCRComplete)
        case .tagged:      chipFiltered = base.filter { !$0.tags.isEmpty }
        case .png:         chipFiltered = base.filter { $0.format == "PNG" }
        case .thisWeek:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            chipFiltered = base.filter { $0.createdAt > cutoff }
        }
        return searchService.filter(
            chipFiltered,
            query: searchQuery,
            collectionNamesByScreenshotID: collectionNamesByScreenshotID,
            detectedCodesByScreenshotID: detectedCodesByScreenshotUUID
        )
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
        0
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

    func createNewCollection() {
        let name = nextCollectionName()
        do {
            let collection = try collectionRepository.createCollection(name: name)
            refreshOrganizationState(pruneSelection: false)
            sidebarSelection = .collection(collection.uuid)
            showToast("Created collection \(collection.name)", kind: .success)
        } catch {
            print("[AppState] create collection failed: \(error)")
            showToast("Could not create collection", kind: .info)
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
        do {
            try tagRepository.addTag(name: name, toScreenshots: screenshotUUIDs)
            refreshOrganizationState(pruneSelection: false)
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
        do {
            try collectionRepository.addScreenshots(screenshotUUIDs, toCollection: collectionUUID)
            refreshOrganizationState(pruneSelection: false)
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

    // MARK: - OCR

    func startOCRQueue() {
        guard database != nil else { return }
        ocrQueueService.start { [weak self] in
            self?.refreshOCRState()
        }
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
        codeDetectionQueueService.start(screenshots: allScreenshots) { [weak self] in
            self?.refreshDetectedCodes()
        }
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
        let standardized = folderURL.standardizedFileURL
        guard !isInsideLibrary(standardized) else {
            showToast("The library folder cannot be watched", kind: .info)
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

    func checkLibraryIntegrityPlaceholder() {
        showToast("Library integrity check is coming later", kind: .comingSoon)
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
        selection.prune(visible: filteredScreenshots.map(\.id))
    }

    // MARK: - Shortcut targets

    /// Cmd-A from anywhere — single entry point for "select all visible".
    func selectAllVisibleScreenshots() {
        let ids = filteredScreenshots.map(\.id)
        print("[AppState] selectAllVisibleScreenshots; visible=\(ids.count); instance=\(ObjectIdentifier(self))")
        selection.selectAll(in: ids)
    }

    /// Plain Escape from anywhere — single entry point for "clear selection".
    func clearScreenshotSelection() {
        print("[AppState] clearScreenshotSelection; instance=\(ObjectIdentifier(self))")
        selection.clear()
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
            previewedScreenshotID = nil
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
        previewedScreenshotID != nil || renamingScreenshotID != nil || isTagEditorPresented || isCollectionPickerPresented
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
            // Spec: pressing Space again toggles the preview off.
            if self.previewedScreenshotID != nil {
                self.previewedScreenshotID = nil
                return
            }
            let shots = self.selectedScreenshots
            self.router.quickLook(shots)
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
        pruneSelectionToVisible()
        print("[AppState] refresh counts inbox=\(inboxCount) favorites=\(favoriteCount) trash=\(trashCount)")
    }

    func untrash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
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
        pruneSelectionToVisible()
    }

    func setFavorite(ids: Set<UUID>, isFavorite: Bool) {
        guard !ids.isEmpty else { return }
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
        let result = await importService.importURLs(urls)

        applyImportResult(result, selectImported: selectImported)

        if !result.imported.isEmpty {
            showToast(Self.importSummary(
                imported: result.imported.count,
                duplicates: result.duplicates,
                unsupported: unsupportedCount,
                failures: result.failures.count
            ), kind: .success)
        } else if result.duplicates > 0 && result.failures.isEmpty && unsupportedCount == 0 {
            showToast(Self.duplicateMessage(count: result.duplicates), kind: .info)
        } else if result.duplicates > 0 || unsupportedCount > 0 {
            showToast(Self.importSummary(
                imported: 0,
                duplicates: result.duplicates,
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
        if !result.imported.isEmpty {
            ocrQueueService.enqueue(result.imported)
            codeDetectionQueueService.enqueue(result.imported)
        }
        objectWillChange.send()
        refreshOrganizationState(pruneSelection: false)

        if selectImported {
            let importedIDs = Set(result.imported.map(\.id))
            let visibleImportedIDs = filteredScreenshots
                .map(\.id)
                .filter { importedIDs.contains($0) }
            if !visibleImportedIDs.isEmpty {
                selection.selectAll(in: visibleImportedIDs)
            }
        }
    }

    private static func importSummary(
        imported: Int,
        duplicates: Int,
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

    // MARK: - Preview overlay

    func beginPreview(of shot: Screenshot) {
        if renamingScreenshotID != nil { cancelRename() }
        previewedScreenshotID = shot.id
    }

    /// Resolves the currently previewed screenshot.
    var previewedScreenshot: Screenshot? {
        guard let id = previewedScreenshotID else { return nil }
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
    func showToast(_ text: String, kind: ToastMessage.Kind = .info) {
        toast = ToastMessage(text: text, kind: kind)
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

    enum Kind {
        case info
        case success
        case comingSoon
    }
}

private enum RenameError: Error {
    case managedFileMissing
}
