import Foundation

// MARK: - Input / Output types

struct AIRenameSuggestionInput {
    let currentText: String
    let originalFilename: String
    let fileExtension: String
    let ocrText: String
    let detectedLinks: [String]
    let detectedQRCodes: [String]
    let existingTags: [String]
    let collectionName: String?
    let createdAt: Date
    var visionContext: String? = nil
}

struct AIRenameSuggestion {
    let filenameStem: String
    let fullFilename: String
}

struct AITagSuggestionInput {
    let partialText: String
    let filename: String
    let ocrText: String
    let detectedLinks: [String]
    let detectedQRCodes: [String]
    let existingTags: [String]
    let collectionName: String?
    var visionContext: String? = nil
}

// MARK: - Provider protocol

protocol AIInlineSuggestionProvider {
    func suggestRename(input: AIRenameSuggestionInput) async throws -> AIRenameSuggestion?
    func suggestTags(input: AITagSuggestionInput) async throws -> [String]
}

// MARK: - Service

/// Dispatches suggestion requests to the configured provider.
/// Provider is selected from AppPreferences.aiProvider; falls back to local rules on any failure.
final class AIInlineSuggestionService {
    static let shared = AIInlineSuggestionService()

    private let localProvider: any AIInlineSuggestionProvider = LocalRuleBasedSuggestionProvider()

    private init() {}

    func suggestRename(input: AIRenameSuggestionInput, preferences: AppPreferences) async -> AIRenameSuggestion? {
        let provider = resolveProvider(preferences: preferences)
        do {
            return try await provider.suggestRename(input: input)
        } catch {
            print("[AISuggestion] rename failed: \(error.localizedDescription), using local fallback")
            return await localFallbackRename(input: input)
        }
    }

    func suggestTags(input: AITagSuggestionInput, preferences: AppPreferences) async -> [String] {
        let provider = resolveProvider(preferences: preferences)
        do {
            return try await provider.suggestTags(input: input)
        } catch {
            print("[AISuggestion] tags failed: \(error.localizedDescription), using local fallback")
            return await localFallbackTags(input: input)
        }
    }

    // MARK: - Provider resolution

    private func resolveProvider(preferences: AppPreferences) -> any AIInlineSuggestionProvider {
        guard preferences.aiProvider == .googleAIStudioGemma else {
            return localProvider
        }
        guard let key = (try? KeychainService.shared.readGoogleAIStudioAPIKey()) ?? nil,
              !key.isEmpty else {
            print("[AISuggestion] Google AI Studio selected but no API key found, using local rules")
            return localProvider
        }
        return GoogleAIStudioGemmaProvider(apiKey: key, model: preferences.googleAIStudioModel.rawValue)
    }

    // MARK: - Local fallbacks

    private func localFallbackRename(input: AIRenameSuggestionInput) async -> AIRenameSuggestion? {
        try? await localProvider.suggestRename(input: input)
    }

    private func localFallbackTags(input: AITagSuggestionInput) async -> [String] {
        (try? await localProvider.suggestTags(input: input)) ?? []
    }
}
