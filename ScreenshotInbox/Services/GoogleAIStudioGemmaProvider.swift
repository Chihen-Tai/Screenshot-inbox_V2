import Foundation

final class GoogleAIStudioGemmaProvider: AIInlineSuggestionProvider {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let timeout: TimeInterval = 15

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = GoogleAIStudioGemmaProvider.timeout
        config.timeoutIntervalForResource = GoogleAIStudioGemmaProvider.timeout
        self.session = URLSession(configuration: config)
    }

    // MARK: - AIInlineSuggestionProvider

    func suggestRename(input: AIRenameSuggestionInput) async throws -> AIRenameSuggestion? {
        let prompt = renamePrompt(from: input)
        let text = try await generate(prompt: prompt)
        return parseRename(json: text, ext: input.fileExtension)
    }

    func suggestTags(input: AITagSuggestionInput) async throws -> [String] {
        let prompt = tagPrompt(from: input)
        let text = try await generate(prompt: prompt)
        return parseTags(json: text)
    }

    // MARK: - REST

    func generate(prompt: String) async throws -> String {
        guard let url = URL(string: "\(Self.baseURL)/\(model):generateContent") else {
            throw ProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 512
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[GoogleAIStudio] request failed: \(error.localizedDescription)")
            throw ProviderError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[GoogleAIStudio] HTTP \(http.statusCode) response")
            throw ProviderError.httpError(http.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            print("[GoogleAIStudio] request failed: unexpected response structure")
            throw ProviderError.unexpectedResponse
        }
        return text
    }

    // MARK: - Prompt builders

    private func renamePrompt(from input: AIRenameSuggestionInput) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: input.createdAt)
        let ext = input.fileExtension.isEmpty ? "png" : input.fileExtension

        var lines: [String] = [
            "You are an assistant inside a macOS screenshot organizer.",
            "Generate a concise filename suggestion from the provided screenshot metadata.",
            "Use only the provided metadata. Do not invent facts.",
            "Return strict JSON only. No markdown. No explanation.",
            "",
            "Metadata:",
            "- original_filename: \(input.originalFilename)",
            "- user_typed: \(input.currentText)",
            "- extension: \(ext)",
            "- created_date: \(dateStr)",
        ]
        if !input.ocrText.isEmpty {
            lines.append("- ocr_text: \(String(input.ocrText.prefix(400)))")
        }
        if let vision = input.visionContext {
            lines.append("- vision_analysis: \(String(vision.prefix(300)))")
        }
        if !input.detectedLinks.isEmpty {
            lines.append("- detected_links: \(input.detectedLinks.prefix(3).joined(separator: ", "))")
        }
        if !input.detectedQRCodes.isEmpty {
            lines.append("- qr_payloads: \(input.detectedQRCodes.prefix(3).joined(separator: ", "))")
        }
        if !input.existingTags.isEmpty {
            lines.append("- existing_tags: \(input.existingTags.joined(separator: ", "))")
        }
        if let col = input.collectionName {
            lines.append("- collection: \(col)")
        }
        lines += [
            "",
            "Rules for filenameStem: lowercase kebab-case, max 80 chars, no slash/colon/newline/quotes/emoji.",
            "If user_typed is useful, complete it rather than replacing entirely.",
            "",
            "Return JSON only:",
            #"{"filenameStem":"<stem>","fullFilename":"<stem>.\#(ext)","confidence":0.0,"reason":"<short reason>"}"#
        ]
        return lines.joined(separator: "\n")
    }

    private func tagPrompt(from input: AITagSuggestionInput) -> String {
        var lines: [String] = [
            "You are an assistant inside a macOS screenshot organizer.",
            "Suggest 1-5 short tags from the provided screenshot metadata.",
            "Use only the provided metadata. Do not invent facts.",
            "Return strict JSON only. No markdown. No explanation.",
            "",
            "Metadata:",
            "- filename: \(input.filename)",
            "- user_typed: \(input.partialText)",
        ]
        if !input.ocrText.isEmpty {
            lines.append("- ocr_text: \(String(input.ocrText.prefix(400)))")
        }
        if let vision = input.visionContext {
            lines.append("- vision_analysis: \(String(vision.prefix(300)))")
        }
        if !input.detectedLinks.isEmpty {
            lines.append("- detected_links: \(input.detectedLinks.prefix(3).joined(separator: ", "))")
        }
        if !input.detectedQRCodes.isEmpty {
            lines.append("- qr_payloads: \(input.detectedQRCodes.prefix(3).joined(separator: ", "))")
        }
        if !input.existingTags.isEmpty {
            lines.append("- existing_tags (exclude these): \(input.existingTags.joined(separator: ", "))")
        }
        lines += [
            "",
            "Rules: lowercase, no spaces (use hyphen if needed), no duplicates, 1-5 tags.",
            "",
            #"Return JSON only: {"tags":["tag1","tag2"],"confidence":0.0}"#
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON parsers

    private func parseRename(json rawText: String, ext: String) -> AIRenameSuggestion? {
        let cleaned = stripCodeFences(rawText)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stem = obj["filenameStem"] as? String,
              !stem.isEmpty else {
            print("[GoogleAIStudio] JSON parse failed, falling back to local rules")
            return nil
        }
        let safeStem = sanitizeFilename(stem)
        guard !safeStem.isEmpty else {
            print("[GoogleAIStudio] JSON parse failed, falling back to local rules")
            return nil
        }
        let safeExt = ext.isEmpty ? "png" : ext
        return AIRenameSuggestion(filenameStem: safeStem, fullFilename: "\(safeStem).\(safeExt)")
    }

    private func parseTags(json rawText: String) -> [String] {
        let cleaned = stripCodeFences(rawText)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = obj["tags"] as? [String] else {
            print("[GoogleAIStudio] JSON parse failed, falling back to local rules")
            return []
        }
        return tags
            .map { sanitizeTag($0) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .map { $0 }
    }

    private func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        }
        if s.hasSuffix("```") {
            s = s.components(separatedBy: "\n").dropLast().joined(separator: "\n")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeFilename(_ s: String) -> String {
        var result = s.lowercased()
        result = result.replacingOccurrences(of: " ", with: "-")
        result = result.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(result.prefix(80))
    }

    private func sanitizeTag(_ s: String) -> String {
        var result = s.lowercased()
        result = result.replacingOccurrences(of: " ", with: "-")
        result = result.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: - Vision / Image Analysis

    func analyzeImage(fileURL: URL) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        let base64 = data.base64EncodedString()
        let mimeType = mimeType(for: fileURL.pathExtension)

        guard let url = URL(string: "\(Self.baseURL)/\(model):generateContent") else {
            throw ProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": "Describe this screenshot in 2-3 sentences. Focus on the main content: what is shown, what application or context it appears to be from, and any key text visible. Be concise and factual."],
                    ["inline_data": ["mime_type": mimeType, "data": base64]]
                ]
            ]],
            "generationConfig": ["temperature": 0.1, "maxOutputTokens": 256]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            print("[GoogleAIStudio] vision HTTP \(http.statusCode)")
            throw ProviderError.httpError(http.statusCode, String(data: responseData, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw ProviderError.unexpectedResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/png"
        }
    }

    // MARK: - Test Connection

    func testConnection() async -> TestConnectionResult {
        let prompt = #"Return JSON only: {"ok":true}"#
        do {
            let text = try await generate(prompt: prompt)
            let cleaned = stripCodeFences(text)
            if let data = cleaned.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               obj["ok"] as? Bool == true {
                return .connected
            }
            return .connected
        } catch ProviderError.httpError(let code, _) {
            switch code {
            case 401, 403: return .invalidAPIKey
            case 404: return .modelUnavailable
            default: return .networkError("HTTP \(code)")
            }
        } catch ProviderError.networkError(let e) {
            if (e as NSError).code == NSURLErrorTimedOut {
                return .timeout
            }
            return .networkError(e.localizedDescription)
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    enum TestConnectionResult {
        case connected
        case invalidAPIKey
        case modelUnavailable
        case networkError(String)
        case timeout

        var displayText: String {
            switch self {
            case .connected: return "Connected"
            case .invalidAPIKey: return "Failed: invalid API key"
            case .modelUnavailable: return "Failed: model unavailable"
            case .networkError(let msg): return "Failed: \(msg)"
            case .timeout: return "Failed: timeout"
            }
        }

        var isSuccess: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    enum ProviderError: Error {
        case invalidURL
        case networkError(Error)
        case httpError(Int, String)
        case unexpectedResponse
    }
}
