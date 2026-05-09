import SwiftUI

struct TagEntrySheet: View {
    @EnvironmentObject private var appState: AppState

    @State private var suggestion: String = ""
    @State private var suggestionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Tag")
                .font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                TextField("Tag name", text: $appState.pendingTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { appState.commitPendingTag() }
                    .onKeyPress(.tab) {
                        guard !suggestion.isEmpty else { return .ignored }
                        appState.pendingTagText = suggestion
                        suggestion = ""
                        return .handled
                    }
                    .onChange(of: appState.pendingTagText) { _, newValue in
                        scheduleTagSuggestion(for: newValue)
                    }
                if !suggestion.isEmpty {
                    Text("Tab → \(suggestion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: suggestion.isEmpty)
            HStack {
                Spacer()
                Button("Cancel") { appState.cancelTagEditor() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { appState.commitPendingTag() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.pendingTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { scheduleTagSuggestion(for: appState.pendingTagText) }
        .onDisappear { suggestionTask?.cancel() }
    }

    private func scheduleTagSuggestion(for text: String) {
        guard appState.preferences.aiInlineSuggestionsEnabled,
              appState.preferences.aiSuggestTags else {
            suggestion = ""
            return
        }
        suggestionTask?.cancel()
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let shot = appState.tagEditorPrimaryScreenshot
            let ocrText = shot.flatMap { appState.ocrResultsByScreenshotUUID[$0.uuidString] }?.text ?? ""
            let codes = shot.flatMap { appState.detectedCodesByScreenshotUUID[$0.uuidString] } ?? []
            let links = codes.filter(\.isURL).map(\.payload)
            let qrCodes = codes.filter { !$0.isURL }.map(\.payload)
            let existing = shot?.tags ?? []
            let input = AITagSuggestionInput(
                partialText: text,
                filename: shot?.name ?? "",
                ocrText: ocrText,
                detectedLinks: links,
                detectedQRCodes: qrCodes,
                existingTags: existing,
                collectionName: nil as String?
            )
            let results = await AIInlineSuggestionService.shared.suggestTags(input: input, preferences: appState.preferences)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestion = results.first ?? ""
            }
        }
    }
}

struct CollectionPickerSheet: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add to Collection")
                .font(.system(size: 17, weight: .semibold))
            if appState.collections.isEmpty {
                Text("No collections")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            } else {
                VStack(spacing: 2) {
                    ForEach(appState.collections) { collection in
                        Button {
                            appState.addPendingScreenshots(to: collection)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: collection.name == "Chemistry" ? "atom" : "folder")
                                    .frame(width: 18)
                                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                                Text(collection.name)
                                    .foregroundStyle(Theme.SemanticColor.label)
                                Spacer(minLength: 0)
                                Text("\(appState.collectionCount(forUUID: collection.uuid))")
                                    .font(.system(size: 11, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button {
                    appState.createNewCollection(promptForName: false)
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Cancel") { appState.cancelCollectionPicker() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

struct CollectionRenameSheet: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Collection")
                .font(.system(size: 17, weight: .semibold))
            TextField("Collection name", text: $appState.pendingCollectionName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { appState.commitCollectionRename() }
            HStack {
                Spacer()
                Button("Cancel") { appState.cancelCollectionRename() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { appState.commitCollectionRename() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.pendingCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
