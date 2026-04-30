import Foundation

final class OrganizationRuleRepository {
    private let database: Database?
    private let dateFormatter = ISO8601DateFormatter()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(database: Database) {
        self.database = database
    }

    init() {
        self.database = nil
    }

    func create(rule: OrganizationRule) throws -> OrganizationRule {
        var created = rule
        created.id = nil
        if created.uuid.isEmpty {
            created.uuid = UUID().uuidString.lowercased()
        }
        if created.createdAt.timeIntervalSince1970 == 0 {
            created.createdAt = Date()
        }
        guard let database else { return created }
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT INTO organization_rules(
                uuid, name, is_enabled, priority, match_mode,
                conditions_json, actions_json, run_on_import, run_after_ocr,
                created_at, updated_at
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?);
            """)
            try bind(created, into: stmt, includeUpdatedAt: true)
            _ = try stmt.step()
        }
        return try fetch(uuid: created.uuid) ?? created
    }

    func fetchAll() throws -> [OrganizationRule] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) ORDER BY priority ASC, created_at ASC;")
            var rows: [OrganizationRule] = []
            while try stmt.step() {
                rows.append(try row(from: stmt))
            }
            return rows
        }
    }

    func fetchEnabled() throws -> [OrganizationRule] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) WHERE is_enabled = 1 ORDER BY priority ASC, created_at ASC;")
            var rows: [OrganizationRule] = []
            while try stmt.step() {
                rows.append(try row(from: stmt))
            }
            return rows
        }
    }

    func fetch(uuid: String) throws -> OrganizationRule? {
        guard let database else { return nil }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) WHERE uuid = ? LIMIT 1;")
            try stmt.bind(1, uuid.lowercased())
            return try stmt.step() ? try row(from: stmt) : nil
        }
    }

    func update(rule: OrganizationRule) throws {
        guard let database else { return }
        var updated = rule
        updated.updatedAt = Date()
        try database.queue.sync {
            let stmt = try database.prepare("""
            UPDATE organization_rules SET
                name = ?, is_enabled = ?, priority = ?, match_mode = ?,
                conditions_json = ?, actions_json = ?, run_on_import = ?,
                run_after_ocr = ?, updated_at = ?
            WHERE uuid = ?;
            """)
            try stmt.bind(1, updated.name)
            try stmt.bindBool(2, updated.isEnabled)
            try stmt.bind(3, updated.priority)
            try stmt.bind(4, updated.matchMode.rawValue)
            try stmt.bind(5, jsonString(updated.conditions))
            try stmt.bind(6, jsonString(updated.actions))
            try stmt.bindBool(7, updated.runOnImport)
            try stmt.bindBool(8, updated.runAfterOCR)
            try stmt.bind(9, dateFormatter.string(from: updated.updatedAt ?? Date()))
            try stmt.bind(10, updated.uuid.lowercased())
            _ = try stmt.step()
        }
    }

    func delete(uuid: String) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("DELETE FROM organization_rules WHERE uuid = ?;")
            try stmt.bind(1, uuid.lowercased())
            _ = try stmt.step()
        }
    }

    func setEnabled(uuid: String, enabled: Bool) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("UPDATE organization_rules SET is_enabled = ?, updated_at = ? WHERE uuid = ?;")
            try stmt.bindBool(1, enabled)
            try stmt.bind(2, dateFormatter.string(from: Date()))
            try stmt.bind(3, uuid.lowercased())
            _ = try stmt.step()
        }
    }

    func reorder(ruleUUIDsInOrder: [String]) throws {
        guard let database, !ruleUUIDsInOrder.isEmpty else { return }
        try database.queue.sync {
            try database.transaction {
                let stmt = try database.prepare("UPDATE organization_rules SET priority = ?, updated_at = ? WHERE uuid = ?;")
                let now = dateFormatter.string(from: Date())
                for (index, uuid) in ruleUUIDsInOrder.enumerated() {
                    stmt.reset()
                    try stmt.bind(1, index)
                    try stmt.bind(2, now)
                    try stmt.bind(3, uuid.lowercased())
                    _ = try stmt.step()
                }
            }
        }
    }

    func recordRun(ruleUUID: String, screenshotUUID: String, actionsApplied: [String]) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT INTO organization_rule_runs(rule_uuid, screenshot_uuid, actions_applied_json, created_at)
            VALUES(?,?,?,?);
            """)
            try stmt.bind(1, ruleUUID.lowercased())
            try stmt.bind(2, screenshotUUID.lowercased())
            try stmt.bind(3, jsonString(actionsApplied))
            try stmt.bind(4, dateFormatter.string(from: Date()))
            _ = try stmt.step()
        }
    }

    func fetchRuns(for screenshotUUID: String) throws -> [String] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT rule_uuid
            FROM organization_rule_runs
            WHERE screenshot_uuid = ?
            ORDER BY created_at DESC;
            """)
            try stmt.bind(1, screenshotUUID.lowercased())
            var rows: [String] = []
            while try stmt.step() {
                if let uuid = stmt.columnString(0) {
                    rows.append(uuid)
                }
            }
            return rows
        }
    }

    private static let selectColumns = """
    SELECT id, uuid, name, is_enabled, priority, match_mode,
           conditions_json, actions_json, run_on_import, run_after_ocr,
           created_at, updated_at
    FROM organization_rules
    """

    private func bind(_ rule: OrganizationRule, into stmt: Database.Statement, includeUpdatedAt: Bool) throws {
        try stmt.bind(1, rule.uuid.lowercased())
        try stmt.bind(2, rule.name)
        try stmt.bindBool(3, rule.isEnabled)
        try stmt.bind(4, rule.priority)
        try stmt.bind(5, rule.matchMode.rawValue)
        try stmt.bind(6, jsonString(rule.conditions))
        try stmt.bind(7, jsonString(rule.actions))
        try stmt.bindBool(8, rule.runOnImport)
        try stmt.bindBool(9, rule.runAfterOCR)
        try stmt.bind(10, dateFormatter.string(from: rule.createdAt))
        if includeUpdatedAt {
            try stmt.bind(11, rule.updatedAt.map(dateFormatter.string(from:)))
        }
    }

    private func row(from stmt: Database.Statement) throws -> OrganizationRule {
        let conditions: [RuleCondition] = try decodeJSON(stmt.columnString(6) ?? "[]")
        let actions: [RuleAction] = try decodeJSON(stmt.columnString(7) ?? "[]")
        return OrganizationRule(
            id: Int(stmt.columnInt(0)),
            uuid: stmt.columnString(1) ?? UUID().uuidString.lowercased(),
            name: stmt.columnString(2) ?? "",
            isEnabled: stmt.columnInt(3) != 0,
            priority: Int(stmt.columnInt(4)),
            matchMode: RuleMatchMode(rawValue: stmt.columnString(5) ?? "") ?? .all,
            conditions: conditions,
            actions: actions,
            runOnImport: stmt.columnInt(8) != 0,
            runAfterOCR: stmt.columnInt(9) != 0,
            createdAt: dateFormatter.date(from: stmt.columnString(10) ?? "") ?? Date(),
            updatedAt: stmt.columnString(11).flatMap { dateFormatter.date(from: $0) }
        )
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeJSON<T: Decodable>(_ value: String) throws -> T {
        try decoder.decode(T.self, from: Data(value.utf8))
    }
}
