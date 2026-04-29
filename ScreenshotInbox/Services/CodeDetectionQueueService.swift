import Foundation

@MainActor
final class CodeDetectionQueueService {
    private let repository: DetectedCodeRepository
    private let screenshotRepository: ScreenshotRepository
    private let detectionService: CodeDetectionService
    private var pendingIDs: [String] = []
    private var queuedIDs: Set<String> = []
    private var runningIDs: Set<String> = []
    private var isRunning = false
    private var onUpdate: (@MainActor () -> Void)?

    init(
        repository: DetectedCodeRepository,
        screenshotRepository: ScreenshotRepository,
        detectionService: CodeDetectionService
    ) {
        self.repository = repository
        self.screenshotRepository = screenshotRepository
        self.detectionService = detectionService
    }

    func start(screenshots: [Screenshot], onUpdate: @escaping @MainActor () -> Void) {
        self.onUpdate = onUpdate
        enqueue(screenshots)
    }

    func enqueue(_ screenshots: [Screenshot]) {
        let ids = screenshots
            .filter { $0.libraryPath != nil }
            .map(\.uuidString)
        enqueueUUIDs(ids)
    }

    func rerun(_ screenshots: [Screenshot]) {
        do {
            for screenshot in screenshots {
                try repository.deleteCodes(for: screenshot.uuidString)
            }
            onUpdate?()
            enqueue(screenshots)
        } catch {
            print("[CodeDetection] rerun failed: \(error)")
        }
    }

    private func enqueueUUIDs(_ ids: [String]) {
        for id in ids.map({ $0.lowercased() }) {
            guard !queuedIDs.contains(id), !runningIDs.contains(id) else { continue }
            queuedIDs.insert(id)
            pendingIDs.append(id)
        }
        processPending()
    }

    private func processPending() {
        guard !isRunning else { return }
        isRunning = true
        Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        defer { isRunning = false }
        while !pendingIDs.isEmpty {
            let uuid = pendingIDs.removeFirst()
            queuedIDs.remove(uuid)
            guard !runningIDs.contains(uuid) else { continue }
            runningIDs.insert(uuid)
            await process(uuid: uuid)
            runningIDs.remove(uuid)
        }
    }

    private func process(uuid: String) async {
        do {
            guard let screenshotID = UUID(uuidString: uuid),
                  let screenshot = try screenshotRepository.fetchByUUID(screenshotID) else {
                throw CodeDetectionServiceError.missingImage
            }
            let results = try await detectionService.detectCodes(for: screenshot)
            let now = Date()
            let codes = results.map {
                DetectedCode(
                    id: nil,
                    screenshotUUID: uuid,
                    symbology: $0.symbology,
                    payload: $0.payload,
                    isURL: $0.isURL,
                    createdAt: now,
                    updatedAt: now
                )
            }
            try repository.saveCodes(codes, for: uuid)
            #if DEBUG
            print("[CodeDetection] complete \(uuid) codes=\(codes.count)")
            #endif
        } catch {
            print("[CodeDetection] failed \(uuid): \(error)")
        }
        onUpdate?()
    }
}
