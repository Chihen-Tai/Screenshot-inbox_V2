import Foundation

final class OrganizationRuleService {
    private let ruleRepository: OrganizationRuleRepository
    private let screenshotRepository: ScreenshotRepository
    private let tagRepository: TagRepository
    private let collectionRepository: CollectionRepository
    private let ocrRepository: OCRRepository
    private let detectedCodeRepository: DetectedCodeRepository

    init(
        ruleRepository: OrganizationRuleRepository,
        screenshotRepository: ScreenshotRepository,
        tagRepository: TagRepository,
        collectionRepository: CollectionRepository,
        ocrRepository: OCRRepository,
        detectedCodeRepository: DetectedCodeRepository
    ) {
        self.ruleRepository = ruleRepository
        self.screenshotRepository = screenshotRepository
        self.tagRepository = tagRepository
        self.collectionRepository = collectionRepository
        self.ocrRepository = ocrRepository
        self.detectedCodeRepository = detectedCodeRepository
    }

    func runRules(for screenshotUUID: String, trigger: RuleTrigger) async throws -> RuleEvaluationResult {
        guard let uuid = UUID(uuidString: screenshotUUID),
              let screenshot = try screenshotRepository.fetchByUUID(uuid) else {
            return RuleEvaluationResult(screenshotUUID: screenshotUUID.lowercased())
        }
        let rules = try rules(for: trigger)
        let context = try RuleEvaluationContext(
            screenshot: screenshot,
            ocrText: ocrRepository.fetch(for: screenshot.uuidString)?.text,
            detectedCodes: detectedCodeRepository.fetchCodes(for: screenshot.uuidString),
            tags: tagRepository.fetchTags(forScreenshot: screenshot.uuidString).map(\.name),
            collections: collectionNames(containing: screenshot.uuidString)
        )
        var result = RuleEvaluationResult(screenshotUUID: screenshot.uuidString)
        for rule in rules where matches(rule: rule, context: context) {
            let beforeCount = result.appliedActions.count
            try apply(rule.actions, to: screenshot, result: &result)
            if result.appliedActions.count > beforeCount {
                result.matchedRuleUUIDs.append(rule.uuid)
                try ruleRepository.recordRun(
                    ruleUUID: rule.uuid,
                    screenshotUUID: screenshot.uuidString,
                    actionsApplied: Array(result.appliedActions[beforeCount...])
                )
            }
        }
        return result
    }

    func runRules(for screenshotUUIDs: [String], trigger: RuleTrigger) async throws -> BatchRuleEvaluationResult {
        var results: [RuleEvaluationResult] = []
        for uuid in screenshotUUIDs {
            results.append(try await runRules(for: uuid, trigger: trigger))
        }
        return BatchRuleEvaluationResult(results: results)
    }

    func runRulesForAllScreenshots() async throws -> BatchRuleEvaluationResult {
        let screenshots = try screenshotRepository.fetchAll(includeTrashed: false)
        return try await runRules(for: screenshots.map(\.uuidString), trigger: .manual)
    }

    private func rules(for trigger: RuleTrigger) throws -> [OrganizationRule] {
        try ruleRepository.fetchEnabled().filter { rule in
            switch trigger {
            case .importComplete:
                return rule.runOnImport && !rule.conditions.contains { $0.field == .ocrText || $0.field == .qrPayload }
            case .ocrComplete:
                return rule.runAfterOCR
            case .qrComplete:
                return rule.runAfterOCR || rule.runOnImport
            case .manual:
                return true
            }
        }
    }

    private func matches(rule: OrganizationRule, context: RuleEvaluationContext) -> Bool {
        guard !rule.conditions.isEmpty, !rule.actions.isEmpty else { return false }
        let matches = rule.conditions.map { conditionMatches($0, context: context) }
        switch rule.matchMode {
        case .all:
            return matches.allSatisfy { $0 }
        case .any:
            return matches.contains(true)
        }
    }

    private func conditionMatches(_ condition: RuleCondition, context: RuleEvaluationContext) -> Bool {
        let candidates: [String]
        switch condition.field {
        case .sourcePath:
            candidates = [context.sourcePath]
        case .filename:
            candidates = [context.screenshot.name]
        case .ocrText:
            guard let ocrText = context.ocrText, !ocrText.isEmpty else { return false }
            candidates = [ocrText]
        case .qrPayload:
            candidates = context.detectedCodes.map(\.payload)
        case .fileType:
            candidates = [context.screenshot.format]
        case .tag:
            candidates = context.tags
        case .collection:
            candidates = context.collections
        }
        return candidates.contains { compare($0, with: condition) }
    }

    private func compare(_ candidate: String, with condition: RuleCondition) -> Bool {
        let lhs = condition.caseSensitive ? candidate : candidate.lowercased()
        let rhs = condition.caseSensitive ? condition.value : condition.value.lowercased()
        switch condition.operator {
        case .contains:
            return lhs.contains(rhs)
        case .equals:
            return lhs == rhs
        case .startsWith:
            return lhs.hasPrefix(rhs)
        case .endsWith:
            return lhs.hasSuffix(rhs)
        }
    }

    private func apply(_ actions: [RuleAction], to screenshot: Screenshot, result: inout RuleEvaluationResult) throws {
        for action in actions {
            switch action {
            case .addTag(let name):
                let existing = try tagRepository.fetchTags(forScreenshot: screenshot.uuidString)
                guard !existing.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
                try tagRepository.addTag(name: name, toScreenshots: [screenshot.uuidString])
                result.tagsAdded += 1
                result.appliedActions.append("addTag:\(name)")
            case .addToCollection(let nameOrUUID):
                let collection = try resolveCollection(nameOrUUID: nameOrUUID)
                let existingIDs = try collectionRepository.fetchScreenshots(inCollection: collection.uuid)
                    .map(\.uuidString)
                guard !existingIDs.contains(screenshot.uuidString) else { continue }
                try collectionRepository.addScreenshots([screenshot.uuidString], toCollection: collection.uuid)
                result.collectionMembershipsAdded += 1
                result.appliedActions.append("addToCollection:\(collection.name)")
            case .markFavorite(let isFavorite):
                guard screenshot.isFavorite != isFavorite else { continue }
                try screenshotRepository.updateFavorite(ids: [screenshot.id], isFavorite: isFavorite)
                result.favoritesChanged += 1
                result.appliedActions.append("markFavorite:\(isFavorite)")
            }
        }
    }

    private func resolveCollection(nameOrUUID: String) throws -> ScreenshotCollection {
        let trimmed = nameOrUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let byUUID = try collectionRepository.fetchCollection(uuid: trimmed) {
            return byUUID
        }
        if let existing = try collectionRepository.fetchCollections().first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return existing
        }
        return try collectionRepository.createCollection(name: trimmed)
    }

    private func collectionNames(containing screenshotUUID: String) throws -> [String] {
        try collectionRepository.fetchCollections().compactMap { collection in
            let contains = try collectionRepository.fetchScreenshots(inCollection: collection.uuid)
                .contains { $0.uuidString == screenshotUUID }
            return contains ? collection.name : nil
        }
    }
}

private struct RuleEvaluationContext {
    let screenshot: Screenshot
    let ocrText: String?
    let detectedCodes: [DetectedCode]
    let tags: [String]
    let collections: [String]

    var sourcePath: String {
        screenshot.sourceApp ?? screenshot.libraryPath ?? ""
    }
}
