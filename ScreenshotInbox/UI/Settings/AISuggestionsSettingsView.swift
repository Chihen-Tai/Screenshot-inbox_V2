import SwiftUI

struct AISuggestionsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var apiKeyInput: String = ""
    @State private var hasStoredKey: Bool = false
    @State private var keySaveMessage: String = ""
    @State private var testStatus: String = ""
    @State private var testIsSuccess: Bool = false
    @State private var isTesting: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                masterToggle
                if appState.preferences.aiInlineSuggestionsEnabled {
                    suggestionTypeSection
                    providerPickerSection
                    if appState.preferences.aiProvider == .googleAIStudioGemma {
                        googleProviderSection
                    } else {
                        localRulesNote
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { refreshKeyStatus() }
    }

    // MARK: - Master toggle

    private var masterToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable AI inline suggestions", isOn: Binding(
                get: { appState.preferences.aiInlineSuggestionsEnabled },
                set: { appState.preferences.aiInlineSuggestionsEnabled = $0 }
            ))
            .font(.system(size: 13, weight: .medium))
            Text("While typing in Rename or Tag fields, a suggestion appears inline. Press Tab to accept.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Suggest-for toggles

    private var suggestionTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUGGEST FOR")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Toggle("Filename (Rename sheet)", isOn: Binding(
                get: { appState.preferences.aiSuggestFilenames },
                set: { appState.preferences.aiSuggestFilenames = $0 }
            ))
            .font(.system(size: 13))
            Toggle("Tags (Tag editor)", isOn: Binding(
                get: { appState.preferences.aiSuggestTags },
                set: { appState.preferences.aiSuggestTags = $0 }
            ))
            .font(.system(size: 13))
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Provider picker

    private var providerPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUGGESTION PROVIDER")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Picker("Provider", selection: Binding(
                get: { appState.preferences.aiProvider },
                set: { appState.preferences.aiProvider = $0 }
            )) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Local rules note

    private var localRulesNote: some View {
        Text("Rules run entirely on-device. No data leaves your Mac.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    // MARK: - Google provider section

    private var googleProviderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelPickerSection
            apiKeySection
            testConnectionSection
            visionSection
            privacyNote
        }
    }

    private var visionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IMAGE UNDERSTANDING (OPT-IN)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Enable \"Analyze Image with AI\" action in Inspector", isOn: Binding(
                get: { appState.preferences.aiVisionEnabled },
                set: { appState.preferences.aiVisionEnabled = $0 }
            ))
            .font(.system(size: 13))

            if appState.preferences.aiVisionEnabled {
                Toggle("Use vision AI when OCR text is empty", isOn: Binding(
                    get: { appState.preferences.aiVisionOnlyWhenOCREmpty },
                    set: { appState.preferences.aiVisionOnlyWhenOCREmpty = $0 }
                ))
                .font(.system(size: 13))
                .padding(.leading, 18)

                Text("When enabled: if a screenshot has no OCR text, opening the Rename sheet triggers a one-time image analysis in the background. The result is cached and used for better suggestions on subsequent opens. Inline autocomplete always uses text-only requests.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 2)
    }

    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODEL")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Picker("Model", selection: Binding(
                get: { appState.preferences.googleAIStudioModel },
                set: { appState.preferences.googleAIStudioModel = $0 }
            )) {
                ForEach(GoogleAIStudioModel.allCases, id: \.self) { model in
                    Text(model.title).tag(model)
                }
            }
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 2)
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GOOGLE AI STUDIO API KEY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                SecureField(
                    hasStoredKey ? "Key saved — enter new key to replace" : "Paste API key here",
                    text: $apiKeyInput
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(maxWidth: 280)

                Button("Save") { saveAPIKey() }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasStoredKey {
                    Button("Remove") { removeAPIKey() }
                        .foregroundStyle(.red)
                }
            }

            if !keySaveMessage.isEmpty {
                Text(keySaveMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Stored securely in macOS Keychain. Never saved to UserDefaults or logs.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private var testConnectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Test Connection") { runTestConnection() }
                    .disabled(isTesting || !hasStoredKey)

                if isTesting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }

                if !testStatus.isEmpty && !isTesting {
                    Text(testStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(testIsSuccess ? Color.green : Color.red)
                }
            }
            if !hasStoredKey {
                Text("Save an API key above to enable Test Connection.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRIVACY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Google AI Studio suggestions send OCR text and screenshot metadata to Google's Gemini API. Raw screenshots are not uploaded in this phase.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Keychain actions

    private func refreshKeyStatus() {
        hasStoredKey = ((try? KeychainService.shared.readGoogleAIStudioAPIKey()) ?? nil) != nil
        apiKeyInput = ""
        keySaveMessage = ""
    }

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainService.shared.saveGoogleAIStudioAPIKey(key)
            apiKeyInput = ""
            keySaveMessage = "API key saved."
            hasStoredKey = true
            testStatus = ""
        } catch {
            keySaveMessage = "Save failed. Check Keychain permissions."
        }
    }

    private func removeAPIKey() {
        do {
            try KeychainService.shared.deleteGoogleAIStudioAPIKey()
            hasStoredKey = false
            apiKeyInput = ""
            keySaveMessage = "API key removed."
            testStatus = ""
        } catch {
            keySaveMessage = "Remove failed."
        }
    }

    private func runTestConnection() {
        guard let key = (try? KeychainService.shared.readGoogleAIStudioAPIKey()) ?? nil,
              !key.isEmpty else {
            testStatus = "No API key stored."
            testIsSuccess = false
            return
        }
        isTesting = true
        testStatus = ""
        let model = appState.preferences.googleAIStudioModel.rawValue
        Task {
            let provider = GoogleAIStudioGemmaProvider(apiKey: key, model: model)
            let result = await provider.testConnection()
            await MainActor.run {
                testStatus = result.displayText
                testIsSuccess = result.isSuccess
                isTesting = false
            }
        }
    }
}
