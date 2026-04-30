import Foundation

struct OrganizationRule: Identifiable, Hashable {
    var id: Int?
    var uuid: String
    var name: String
    var isEnabled: Bool
    var priority: Int
    var matchMode: RuleMatchMode
    var conditions: [RuleCondition]
    var actions: [RuleAction]
    var runOnImport: Bool
    var runAfterOCR: Bool
    var createdAt: Date
    var updatedAt: Date?

    init(
        id: Int? = nil,
        uuid: String = UUID().uuidString.lowercased(),
        name: String,
        isEnabled: Bool = true,
        priority: Int = 0,
        matchMode: RuleMatchMode = .all,
        conditions: [RuleCondition],
        actions: [RuleAction],
        runOnImport: Bool = true,
        runAfterOCR: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.isEnabled = isEnabled
        self.priority = priority
        self.matchMode = matchMode
        self.conditions = conditions
        self.actions = actions
        self.runOnImport = runOnImport
        self.runAfterOCR = runAfterOCR
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum RuleMatchMode: String, Codable, CaseIterable, Hashable {
    case all
    case any
}

struct RuleCondition: Codable, Hashable, Identifiable {
    var id: String { "\(field.rawValue):\(self.operator.rawValue):\(value):\(caseSensitive)" }
    var field: RuleConditionField
    var `operator`: RuleConditionOperator
    var value: String
    var caseSensitive: Bool

    init(
        field: RuleConditionField,
        operator: RuleConditionOperator,
        value: String,
        caseSensitive: Bool = false
    ) {
        self.field = field
        self.operator = `operator`
        self.value = value
        self.caseSensitive = caseSensitive
    }
}

enum RuleConditionField: String, Codable, CaseIterable, Hashable {
    case sourcePath
    case filename
    case ocrText
    case qrPayload
    case fileType
    case tag
    case collection
}

enum RuleConditionOperator: String, Codable, CaseIterable, Hashable {
    case contains
    case equals
    case startsWith
    case endsWith
}

enum RuleAction: Codable, Hashable, Identifiable {
    case addTag(name: String)
    case addToCollection(nameOrUUID: String)
    case markFavorite(Bool)

    var id: String {
        switch self {
        case .addTag(let name): return "addTag:\(name)"
        case .addToCollection(let nameOrUUID): return "addToCollection:\(nameOrUUID)"
        case .markFavorite(let value): return "markFavorite:\(value)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case nameOrUUID
        case value
    }

    private enum ActionType: String, Codable {
        case addTag
        case addToCollection
        case markFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        switch type {
        case .addTag:
            self = .addTag(name: try container.decode(String.self, forKey: .name))
        case .addToCollection:
            self = .addToCollection(nameOrUUID: try container.decode(String.self, forKey: .nameOrUUID))
        case .markFavorite:
            self = .markFavorite(try container.decode(Bool.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .addTag(let name):
            try container.encode(ActionType.addTag, forKey: .type)
            try container.encode(name, forKey: .name)
        case .addToCollection(let nameOrUUID):
            try container.encode(ActionType.addToCollection, forKey: .type)
            try container.encode(nameOrUUID, forKey: .nameOrUUID)
        case .markFavorite(let value):
            try container.encode(ActionType.markFavorite, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

enum RuleTrigger: String, Hashable {
    case importComplete
    case ocrComplete
    case qrComplete
    case manual
}

struct RuleEvaluationResult: Hashable {
    var screenshotUUID: String
    var matchedRuleUUIDs: [String] = []
    var appliedActions: [String] = []
    var tagsAdded: Int = 0
    var collectionMembershipsAdded: Int = 0
    var favoritesChanged: Int = 0
}

struct BatchRuleEvaluationResult: Hashable {
    var results: [RuleEvaluationResult]

    var screenshotsChanged: Int {
        results.filter { !$0.appliedActions.isEmpty }.count
    }

    var tagsAdded: Int {
        results.reduce(0) { $0 + $1.tagsAdded }
    }

    var collectionMembershipsAdded: Int {
        results.reduce(0) { $0 + $1.collectionMembershipsAdded }
    }

    var favoritesChanged: Int {
        results.reduce(0) { $0 + $1.favoritesChanged }
    }
}
