import Foundation

@MainActor
final class OCRQueueService {
    private let repository: OCRRepository
    private let screenshotRepository: ScreenshotRepository
    private let ocrService: OCRService
    private var runningIDs: Set<String> = []
    private var isRunning = false
    private var onUpdate: (@MainActor () -> Void)?

    init(
        repository: OCRRepository,
        screenshotRepository: ScreenshotRepository,
        ocrService: OCRService
    ) {
        self.repository = repository
        self.screenshotRepository = screenshotRepository
        self.ocrService = ocrService
    }

    func start(onUpdate: @escaping @MainActor () -> Void) {
        self.onUpdate = onUpdate
        do {
            try repository.resetProcessingToPending()
        } catch {
            print("[OCR] reset processing failed: \(error)")
        }
        processPending()
    }

    func enqueue(_ screenshots: [Screenshot]) {
        do {
            try repository.ensurePending(for: screenshots.map(\.uuidString))
            processPending()
        } catch {
            print("[OCR] enqueue failed: \(error)")
        }
    }

    func rerun(_ screenshots: [Screenshot]) {
        do {
            try repository.resetToPending(screenshotUUIDs: screenshots.map(\.uuidString))
            onUpdate?()
            processPending()
        } catch {
            print("[OCR] rerun failed: \(error)")
        }
    }

    func processPending() {
        guard !isRunning else { return }
        isRunning = true
        Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        defer { isRunning = false }
        while true {
            let pending: [OCRResult]
            do {
                pending = try repository.fetchPending(limit: 1)
            } catch {
                print("[OCR] fetch pending failed: \(error)")
                return
            }
            guard let job = pending.first else { return }
            let uuid = job.screenshotUUID.lowercased()
            guard !runningIDs.contains(uuid) else { return }
            runningIDs.insert(uuid)
            await process(job)
            runningIDs.remove(uuid)
        }
    }

    private func process(_ job: OCRResult) async {
        do {
            try repository.markProcessing(screenshotUUID: job.screenshotUUID)
            onUpdate?()
            guard let uuid = UUID(uuidString: job.screenshotUUID),
                  let screenshot = try screenshotRepository.fetchByUUID(uuid) else {
                throw OCRServiceError.missingImage
            }
            let result = try await ocrService.recognizeText(for: screenshot)
            try repository.saveResult(
                screenshotUUID: job.screenshotUUID,
                text: result.text,
                language: result.language,
                confidence: result.confidence
            )
            #if DEBUG
            print("[OCR] complete \(job.screenshotUUID) chars=\(result.text.count)")
            #endif
        } catch {
            do {
                try repository.markFailed(screenshotUUID: job.screenshotUUID, error: String(describing: error))
            } catch {
                print("[OCR] mark failed failed: \(error)")
            }
            print("[OCR] failed \(job.screenshotUUID): \(error)")
        }
        onUpdate?()
    }
}
