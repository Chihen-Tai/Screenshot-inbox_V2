import Foundation

final class LocalRuleBasedSuggestionProvider: AIInlineSuggestionProvider {

    // MARK: - Rename

    func suggestRename(input: AIRenameSuggestionInput) async throws -> AIRenameSuggestion? {
        let ocr = input.ocrText.lowercased()
        let ext = input.fileExtension.isEmpty ? "png" : input.fileExtension

        // QR / link → domain-based name
        if let link = input.detectedLinks.first ?? input.detectedQRCodes.first,
           let host = URL(string: link)?.host {
            let slug = kebab(host.replacingOccurrences(of: "www.", with: ""))
            let stem = truncate("link-\(slug)")
            return suggestion(stem: stem, ext: ext)
        }

        // OCR keyword → category + slug
        if let matched = categoryMatch(ocr: ocr) {
            return suggestion(stem: matched, ext: ext)
        }

        // Date-based fallback
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let datePart = formatter.string(from: input.createdAt)
        return suggestion(stem: "screenshot-\(datePart)", ext: ext)
    }

    // MARK: - Tags

    func suggestTags(input: AITagSuggestionInput) async throws -> [String] {
        let partial = input.partialText.lowercased()
        let ocr = input.ocrText.lowercased()
        var results: [String] = []

        // 1. Vocabulary prefix completion
        if !partial.isEmpty {
            let matches = vocabulary.filter { $0.hasPrefix(partial) && $0 != partial }
            results.append(contentsOf: matches.prefix(3))
        }

        // 2. OCR keyword rules
        for (keywords, tag) in ocrTagRules {
            guard !results.contains(tag) else { continue }
            if keywords.contains(where: { ocr.contains($0) }) {
                results.append(tag)
            }
        }

        // 3. QR / link
        if !(input.detectedLinks.isEmpty && input.detectedQRCodes.isEmpty) {
            if !results.contains("link") { results.append("link") }
            if !results.contains("qr") { results.append("qr") }
        }

        // Exclude already-applied tags
        return results.filter { !input.existingTags.contains($0) }.prefix(5).map { $0 }
    }

    // MARK: - OCR category patterns

    private func categoryMatch(ocr: String) -> String? {
        for (keywords, category) in ocrCategoryRules {
            if keywords.contains(where: { ocr.contains($0) }) {
                let slug = primaryKeyword(from: ocr, keywords: keywords)
                return truncate("\(category)-\(slug)")
            }
        }
        return nil
    }

    private func primaryKeyword(from ocr: String, keywords: [String]) -> String {
        let found = keywords.first(where: { ocr.contains($0) }) ?? ""
        return kebab(found)
    }

    // MARK: - Helpers

    private func suggestion(stem: String, ext: String) -> AIRenameSuggestion {
        AIRenameSuggestion(filenameStem: stem, fullFilename: "\(stem).\(ext)")
    }

    private func kebab(_ s: String) -> String {
        var result = s.lowercased()
        result = result.replacingOccurrences(of: " ", with: "-")
        result = result.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func truncate(_ s: String, limit: Int = 60) -> String {
        guard s.count > limit else { return s }
        let words = s.split(separator: "-")
        var out = ""
        for word in words {
            let candidate = out.isEmpty ? String(word) : "\(out)-\(word)"
            if candidate.count > limit { break }
            out = candidate
        }
        return out.isEmpty ? String(s.prefix(limit)) : out
    }

    // MARK: - Rule tables

    private let ocrCategoryRules: [([String], String)] = [
        (["error", "exception", "traceback", "fatal", "build failed", "compile"], "error"),
        (["warning", "deprecated", "warn:"], "warning"),
        (["terminal", "bash", "zsh", "$ ", "% ", "command not found"], "terminal"),
        (["swift", "func ", "class ", "struct ", "var ", "let "], "code"),
        (["python", "def ", "import ", "pip install"], "code"),
        (["git ", "commit", "branch", "merge", "pull request"], "git"),
        (["receipt", "invoice", "total", "subtotal", "payment", "order #"], "receipt"),
        (["stock", "shares", "dividend", "portfolio", "profit", "loss"], "finance"),
        (["equation", "formula", "theorem", "proof", "integral", "∑", "∫"], "math"),
        (["element", "compound", "molecule", "reaction", "chemistry"], "chemistry"),
        (["schedule", "meeting", "calendar", "agenda", "event"], "schedule"),
        (["message", "chat", "inbox", "reply", "from:", "to:"], "message"),
        (["http", "url", "www.", "api", "endpoint", "request"], "web"),
        (["password", "login", "username", "sign in", "authentication"], "auth"),
        (["map", "location", "address", "directions", "coordinates"], "map"),
    ]

    private let ocrTagRules: [([String], String)] = [
        (["error", "exception", "fatal"], "error"),
        (["warning", "deprecated"], "warning"),
        (["terminal", "bash", "zsh"], "terminal"),
        (["swift", "python", "javascript", "func ", "def "], "code"),
        (["git", "commit", "branch", "merge"], "git"),
        (["receipt", "invoice", "payment"], "receipt"),
        (["stock", "shares", "finance", "portfolio"], "finance"),
        (["formula", "equation", "theorem"], "math"),
        (["chemistry", "molecule", "element"], "chemistry"),
        (["meeting", "schedule", "calendar"], "schedule"),
        (["message", "chat", "inbox"], "message"),
        (["map", "location", "address"], "map"),
        (["diagram", "chart", "graph", "table"], "diagram"),
        (["screenshot", "screen recording", "screen capture"], "screen"),
    ]

    private let vocabulary: [String] = [
        "code", "chemistry", "chart", "calendar",
        "diagram", "design", "docs", "debug",
        "error", "export",
        "finance", "formula",
        "git",
        "important",
        "link", "log",
        "math", "message", "map",
        "note",
        "qa", "qr",
        "receipt", "reference",
        "schedule", "screenshot", "screen",
        "terminal",
        "ui", "urgent",
        "warning", "web", "work",
    ]
}
