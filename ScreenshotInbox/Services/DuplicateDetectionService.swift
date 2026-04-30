import Foundation

/// Detects duplicate or near-duplicate screenshots.
final class DuplicateDetectionService {
    private let screenshotRepository: ScreenshotRepository?
    private let imageHashRepository: ImageHashRepository?
    private let similarThreshold: Int

    init(
        screenshotRepository: ScreenshotRepository,
        imageHashRepository: ImageHashRepository,
        similarThreshold: Int = 6
    ) {
        self.screenshotRepository = screenshotRepository
        self.imageHashRepository = imageHashRepository
        self.similarThreshold = similarThreshold
    }

    init() {
        self.screenshotRepository = nil
        self.imageHashRepository = nil
        self.similarThreshold = 6
    }

    func fetchDuplicateGroups(includeTrashed: Bool = false) throws -> [DuplicateGroup] {
        guard let screenshotRepository, let imageHashRepository else { return [] }
        let screenshots = try screenshotRepository.fetchAll(includeTrashed: includeTrashed)
        let hashes = try imageHashRepository.fetchAll()
        return Self.findDuplicateGroups(
            screenshots: screenshots,
            imageHashes: hashes,
            includeTrashed: includeTrashed,
            similarThreshold: similarThreshold
        )
    }

    func fetchDuplicateCount(includeTrashed: Bool = false) throws -> Int {
        try fetchDuplicateGroups(includeTrashed: includeTrashed)
            .reduce(into: Set<String>()) { ids, group in
                ids.formUnion(group.screenshotUUIDs)
            }
            .count
    }

    static func findDuplicateGroups(
        screenshots: [Screenshot],
        imageHashes: [String: ImageHashRecord],
        includeTrashed: Bool,
        similarThreshold: Int = 6
    ) -> [DuplicateGroup] {
        let candidates = screenshots
            .filter { includeTrashed || !$0.isTrashed }
        let byUUID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.uuidString, $0) })
        var groups: [DuplicateGroup] = []
        var assignedSimilarUUIDs: Set<String> = []

        let exactBuckets = Dictionary(grouping: candidates) { screenshot in
            screenshot.fileHash?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }
        for (hash, bucket) in exactBuckets where !hash.isEmpty && bucket.count > 1 {
            let ordered = stableOrder(bucket)
            let ids = ordered.map(\.uuidString)
            let keep = recommendedKeep(in: ordered)
            groups.append(DuplicateGroup(
                id: "exact-\(hash)",
                kind: .exact,
                screenshotUUIDs: ids,
                confidence: 1.0,
                createdAt: nil,
                recommendedKeepUUID: keep?.uuidString
            ))
            assignedSimilarUUIDs.formUnion(ids)
        }

        let hashItems = candidates
            .filter { !assignedSimilarUUIDs.contains($0.uuidString) }
            .compactMap { screenshot -> (Screenshot, UInt64)? in
                guard let record = imageHashes[screenshot.uuidString],
                      record.algorithm == ImageHashRecord.dHashAlgorithm,
                      let value = UInt64(record.hash, radix: 16) else {
                    return nil
                }
                return (screenshot, value)
            }

        var visited: Set<String> = []
        for index in hashItems.indices {
            let (seed, seedHash) = hashItems[index]
            guard !visited.contains(seed.uuidString) else { continue }
            var bucket: [Screenshot] = [seed]
            for otherIndex in hashItems.index(after: index)..<hashItems.endIndex {
                let (other, otherHash) = hashItems[otherIndex]
                guard !visited.contains(other.uuidString) else { continue }
                if hammingDistance(seedHash, otherHash) <= similarThreshold {
                    bucket.append(other)
                }
            }
            guard bucket.count > 1 else { continue }
            let ordered = stableOrder(bucket)
            let ids = ordered.map(\.uuidString)
            visited.formUnion(ids)
            let keep = recommendedKeep(in: ordered)
            let distances = ordered.compactMap { shot -> Int? in
                guard let record = imageHashes[shot.uuidString],
                      let value = UInt64(record.hash, radix: 16) else { return nil }
                return hammingDistance(seedHash, value)
            }
            let maxDistance = distances.max() ?? similarThreshold
            let confidence = max(0.0, 1.0 - (Double(maxDistance) / 64.0))
            groups.append(DuplicateGroup(
                id: "similar-\(ids.joined(separator: "-"))",
                kind: .similar,
                screenshotUUIDs: ids,
                confidence: confidence,
                createdAt: nil,
                recommendedKeepUUID: keep?.uuidString
            ))
        }

        return groups.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .exact }
            if lhs.screenshotUUIDs.count != rhs.screenshotUUIDs.count {
                return lhs.screenshotUUIDs.count > rhs.screenshotUUIDs.count
            }
            let leftDate = lhs.screenshotUUIDs.compactMap { byUUID[$0]?.importedAt ?? byUUID[$0]?.createdAt }.min() ?? .distantFuture
            let rightDate = rhs.screenshotUUIDs.compactMap { byUUID[$0]?.importedAt ?? byUUID[$0]?.createdAt }.min() ?? .distantFuture
            return leftDate < rightDate
        }
    }

    static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    static func recommendedKeep(in screenshots: [Screenshot]) -> Screenshot? {
        screenshots.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            let leftPixels = lhs.pixelWidth * lhs.pixelHeight
            let rightPixels = rhs.pixelWidth * rhs.pixelHeight
            if leftPixels != rightPixels { return leftPixels > rightPixels }
            let leftDate = lhs.importedAt ?? lhs.createdAt
            let rightDate = rhs.importedAt ?? rhs.createdAt
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.uuidString < rhs.uuidString
        }.first
    }

    private static func stableOrder(_ screenshots: [Screenshot]) -> [Screenshot] {
        screenshots.sorted {
            let leftDate = $0.importedAt ?? $0.createdAt
            let rightDate = $1.importedAt ?? $1.createdAt
            if leftDate != rightDate { return leftDate < rightDate }
            return $0.uuidString < $1.uuidString
        }
    }
}
