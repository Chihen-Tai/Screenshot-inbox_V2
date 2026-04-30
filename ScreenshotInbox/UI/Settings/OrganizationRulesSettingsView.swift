import SwiftUI

struct OrganizationRulesSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var ruleName = ""
    @State private var field: RuleConditionField = .filename
    @State private var conditionValue = ""
    @State private var tagName = ""
    @State private var collectionName = ""
    @State private var runOnImport = true
    @State private var runAfterOCR = true
    @State private var editingRuleUUID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            SettingsSection(title: "Rules") {
                if appState.organizationRules.isEmpty {
                    SettingsNote(text: "No rules yet. Add a simple rule below to tag or collect screenshots automatically.")
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                        ForEach(appState.organizationRules) { rule in
                                OrganizationRuleRow(rule: rule) {
                                    load(rule)
                                }
                                    .environmentObject(appState)
                            }
                        }
                    }
                    .frame(maxHeight: 170)
                }
            }
            SettingsSection(title: "Add Simple Rule") {
                addRuleForm
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .onAppear { appState.refreshOrganizationRules() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Smart Organization")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    appState.runRulesNowForSelection()
                } label: {
                    Label("Run Selected", systemImage: "play")
                }
                Button {
                    appState.runRulesNowForAllScreenshots()
                } label: {
                    Label("Run All", systemImage: "play.fill")
                }
            }
            Text("Local rules can add tags and collection memberships after import, OCR, or a manual run.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
        }
    }

    private var addRuleForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Rule name", text: $ruleName)
            HStack {
                Text("IF")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                Picker("", selection: $field) {
                    Text("Filename").tag(RuleConditionField.filename)
                    Text("Source path").tag(RuleConditionField.sourcePath)
                    Text("OCR text").tag(RuleConditionField.ocrText)
                    Text("QR payload").tag(RuleConditionField.qrPayload)
                    Text("File type").tag(RuleConditionField.fileType)
                }
                .labelsHidden()
                .frame(width: 140)
                Text("contains")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                TextField("text", text: $conditionValue)
            }
            HStack {
                Text("THEN")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                TextField("add tag", text: $tagName)
                TextField("add to collection (optional)", text: $collectionName)
            }
            HStack {
                Toggle("Run on import", isOn: $runOnImport)
                Toggle("Run after OCR", isOn: $runAfterOCR)
                Spacer()
                if editingRuleUUID != nil {
                    Button("Cancel") {
                        clearForm()
                    }
                }
                Button {
                    if let editingRuleUUID {
                        appState.updateOrganizationRule(
                            uuid: editingRuleUUID,
                            name: ruleName,
                            field: field,
                            value: conditionValue,
                            tagName: tagName,
                            collectionName: collectionName,
                            runOnImport: runOnImport,
                            runAfterOCR: runAfterOCR
                        )
                    } else {
                        appState.createOrganizationRule(
                            name: ruleName,
                            field: field,
                            value: conditionValue,
                            tagName: tagName,
                            collectionName: collectionName,
                            runOnImport: runOnImport,
                            runAfterOCR: runAfterOCR
                        )
                    }
                    clearForm()
                } label: {
                    Label(editingRuleUUID == nil ? "Add Rule" : "Save Rule",
                          systemImage: editingRuleUUID == nil ? "plus" : "checkmark")
                }
            }
        }
    }

    private func load(_ rule: OrganizationRule) {
        editingRuleUUID = rule.uuid
        ruleName = rule.name
        if let condition = rule.conditions.first {
            field = condition.field
            conditionValue = condition.value
        }
        tagName = rule.actions.compactMap { action -> String? in
            if case .addTag(let name) = action { return name }
            return nil
        }.first ?? ""
        collectionName = rule.actions.compactMap { action -> String? in
            if case .addToCollection(let nameOrUUID) = action { return nameOrUUID }
            return nil
        }.first ?? ""
        runOnImport = rule.runOnImport
        runAfterOCR = rule.runAfterOCR
    }

    private func clearForm() {
        editingRuleUUID = nil
        ruleName = ""
        conditionValue = ""
        tagName = ""
        collectionName = ""
    }
}

private struct OrganizationRuleRow: View {
    @EnvironmentObject private var appState: AppState
    let rule: OrganizationRule
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { appState.setOrganizationRuleEnabled(rule, enabled: $0) }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.system(size: 13, weight: .medium))
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            .help("Edit rule")
            Button {
                appState.deleteOrganizationRule(rule)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            .help("Delete rule")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.SemanticColor.quietFill.opacity(0.35))
        )
    }

    private var summary: String {
        let condition = rule.conditions.first.map {
            "\($0.field.rawValue) \($0.operator.rawValue) \"\($0.value)\""
        } ?? "No condition"
        let actions = rule.actions.map { action -> String in
            switch action {
            case .addTag(let name):
                return "tag \(name)"
            case .addToCollection(let nameOrUUID):
                return "collection \(nameOrUUID)"
            case .markFavorite(let value):
                return value ? "favorite" : "unfavorite"
            }
        }.joined(separator: ", ")
        return "\(condition) -> \(actions)"
    }
}
