import Foundation
import Testing
@testable import ScreenshotInbox

struct OrganizationRuleTests {
    @Test
    func repositoryRoundTripsRuleConditionsAndActions() throws {
        let database = try makeDatabase()
        let repository = OrganizationRuleRepository(database: database)
        let rule = OrganizationRule(
            name: "Chemistry filenames",
            priority: 2,
            matchMode: .all,
            conditions: [
                RuleCondition(field: .filename, operator: .contains, value: "chem", caseSensitive: false)
            ],
            actions: [
                .addTag(name: "chemistry"),
                .addToCollection(nameOrUUID: "Papers")
            ],
            runOnImport: true,
            runAfterOCR: false
        )

        let created = try repository.create(rule: rule)
        let fetched = try #require(try repository.fetchAll().first)

        #expect(fetched.uuid == created.uuid)
        #expect(fetched.name == "Chemistry filenames")
        #expect(fetched.priority == 2)
        #expect(fetched.conditions == rule.conditions)
        #expect(fetched.actions == rule.actions)
        #expect(fetched.runOnImport == true)
        #expect(fetched.runAfterOCR == false)
    }

    @Test
    func serviceAppliesFilenameRuleWithoutDuplicatingTagOrCollectionMembership() async throws {
        let database = try makeDatabase()
        let screenshotRepository = ScreenshotRepository(database: database)
        let tagRepository = TagRepository(database: database)
        let collectionRepository = CollectionRepository(database: database)
        let ruleRepository = OrganizationRuleRepository(database: database)
        let ocrRepository = OCRRepository(database: database)
        let codeRepository = DetectedCodeRepository(database: database)
        let screenshot = makeScreenshot(name: "chem_test.png", sourcePath: "/tmp/screenshot-inbox-tests/downloads")
        let collection = try collectionRepository.createCollection(name: "Chemistry")
        try screenshotRepository.insert(screenshot)
        _ = try ruleRepository.create(rule: OrganizationRule(
            name: "Chemistry",
            conditions: [
                RuleCondition(field: .filename, operator: .contains, value: "chem", caseSensitive: false)
            ],
            actions: [
                .addTag(name: "chemistry"),
                .addToCollection(nameOrUUID: collection.uuid)
            ]
        ))
        let service = OrganizationRuleService(
            ruleRepository: ruleRepository,
            screenshotRepository: screenshotRepository,
            tagRepository: tagRepository,
            collectionRepository: collectionRepository,
            ocrRepository: ocrRepository,
            detectedCodeRepository: codeRepository
        )

        _ = try await service.runRules(for: screenshot.uuidString, trigger: .manual)
        let second = try await service.runRules(for: screenshot.uuidString, trigger: .manual)

        let tags = try tagRepository.fetchTags(forScreenshot: screenshot.uuidString).map(\.name)
        let collectionItems = try collectionRepository.fetchScreenshots(inCollection: collection.uuid)

        #expect(tags == ["chemistry"])
        #expect(collectionItems.map(\.id) == [screenshot.id])
        #expect(second.tagsAdded == 0)
        #expect(second.collectionMembershipsAdded == 0)
    }

    @Test
    func ocrConditionMatchesOnlyAfterOCRTextExists() async throws {
        let database = try makeDatabase()
        let screenshotRepository = ScreenshotRepository(database: database)
        let tagRepository = TagRepository(database: database)
        let collectionRepository = CollectionRepository(database: database)
        let ruleRepository = OrganizationRuleRepository(database: database)
        let ocrRepository = OCRRepository(database: database)
        let codeRepository = DetectedCodeRepository(database: database)
        let screenshot = makeScreenshot(name: "plain.png", sourcePath: "/tmp")
        try screenshotRepository.insert(screenshot)
        _ = try ruleRepository.create(rule: OrganizationRule(
            name: "MATLAB OCR",
            conditions: [
                RuleCondition(field: .ocrText, operator: .contains, value: "MATLAB", caseSensitive: false)
            ],
            actions: [.addTag(name: "matlab")],
            runOnImport: true,
            runAfterOCR: true
        ))
        let service = OrganizationRuleService(
            ruleRepository: ruleRepository,
            screenshotRepository: screenshotRepository,
            tagRepository: tagRepository,
            collectionRepository: collectionRepository,
            ocrRepository: ocrRepository,
            detectedCodeRepository: codeRepository
        )

        let before = try await service.runRules(for: screenshot.uuidString, trigger: .importComplete)
        try ocrRepository.saveResult(screenshotUUID: screenshot.uuidString, text: "plot MATLAB data", language: "en", confidence: 0.9)
        let after = try await service.runRules(for: screenshot.uuidString, trigger: .ocrComplete)

        #expect(before.tagsAdded == 0)
        #expect(after.tagsAdded == 1)
        #expect(try tagRepository.fetchTags(forScreenshot: screenshot.uuidString).map(\.name) == ["matlab"])
    }

    private func makeDatabase() throws -> Database {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxRuleTests-\(UUID().uuidString).sqlite")
        let database = try Database(path: url.path)
        let migrations = MigrationManager()
        migrations.register(.initialSchema)
        migrations.register(.organizationSchema)
        migrations.register(.ocrSchema)
        migrations.register(.detectedCodesSchema)
        migrations.register(.organizationRulesSchema)
        try migrations.runPending(on: database)
        return database
    }

    private func makeScreenshot(name: String, sourcePath: String) -> Screenshot {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 100)
        return Screenshot(
            id: id,
            name: name,
            createdAt: date,
            pixelWidth: 100,
            pixelHeight: 100,
            byteSize: 100,
            format: "PNG",
            tags: [],
            ocrSnippets: [],
            isFavorite: false,
            isOCRComplete: false,
            thumbnailKind: .document,
            isTrashed: false,
            libraryPath: "Originals/2026/04/\(id.uuidString.lowercased()).png",
            fileHash: UUID().uuidString,
            importedAt: date,
            modifiedAt: date,
            sourceApp: sourcePath,
            sortIndex: 0,
            trashDate: nil
        )
    }
}
