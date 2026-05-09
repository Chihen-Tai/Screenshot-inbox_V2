import SwiftUI

/// Phase 5 — modal sheet for renaming a single screenshot.
/// Bound to `AppState.pendingRenameText`; commit/cancel funnel through
/// `AppState.commitRename` / `cancelRename` so the rest of the app sees
/// the new name through the existing `objectWillChange` plumbing.
struct RenameSheet: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var fieldFocused: Bool

    let screenshot: Screenshot

    @State private var suggestion: String = ""
    @State private var suggestionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Screenshot")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.SemanticColor.label)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                TextField("", text: $appState.pendingRenameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($fieldFocused)
                    .onSubmit { appState.commitRename() }
                    .onKeyPress(.tab) {
                        guard !suggestion.isEmpty else { return .ignored }
                        appState.pendingRenameText = suggestion
                        suggestion = ""
                        return .handled
                    }
                    .onChange(of: appState.pendingRenameText) { _, newValue in
                        scheduleSuggestion(for: newValue)
                    }
                if !suggestion.isEmpty {
                    Text("Tab → \(suggestion)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .transition(.opacity)
                }
                Text("This always renames the managed Screenshot Inbox copy. Original source files are renamed only when Source Folder Sync is enabled.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { appState.cancelRename() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { appState.commitRename() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || trimmed == screenshot.name)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            fieldFocused = true
            scheduleSuggestion(for: appState.pendingRenameText)
        }
        .onDisappear {
            suggestionTask?.cancel()
        }
        .animation(.easeInOut(duration: 0.15), value: suggestion.isEmpty)
    }

    private var trimmed: String {
        appState.pendingRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleSuggestion(for text: String) {
        guard appState.preferences.aiInlineSuggestionsEnabled,
              appState.preferences.aiSuggestFilenames else {
            suggestion = ""
            return
        }
        suggestionTask?.cancel()
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let ocrText = appState.ocrResultsByScreenshotUUID[screenshot.uuidString]?.text ?? ""
            let codes = appState.detectedCodesByScreenshotUUID[screenshot.uuidString] ?? []
            let links = codes.filter(\.isURL).compactMap { $0.payload }
            let qrCodes = codes.filter { !$0.isURL }.compactMap { $0.payload }
            let visionContext = appState.cachedVisionAnalysis(for: screenshot)
            if visionContext == nil,
               appState.preferences.aiVisionEnabled,
               appState.preferences.aiVisionOnlyWhenOCREmpty,
               ocrText.isEmpty {
                appState.analyzeImageWithAI(screenshot: screenshot)
            }
            let input = AIRenameSuggestionInput(
                currentText: text,
                originalFilename: screenshot.name,
                fileExtension: URL(fileURLWithPath: screenshot.name).pathExtension,
                ocrText: ocrText,
                detectedLinks: links,
                detectedQRCodes: qrCodes,
                existingTags: screenshot.tags,
                collectionName: nil as String?,
                createdAt: screenshot.createdAt,
                visionContext: visionContext
            )
            let result = await AIInlineSuggestionService.shared.suggestRename(input: input, preferences: appState.preferences)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let stem = result?.filenameStem ?? ""
                suggestion = (stem.isEmpty || stem == trimmed) ? "" : stem
            }
        }
    }
}
