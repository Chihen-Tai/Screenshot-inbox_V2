import Foundation

final class SearchService {
    init() {}

    func parsedQuery(_ query: String) -> ParsedSearchQuery {
        ParsedSearchQuery(rawQuery: query)
    }

    func filter(
        _ screenshots: [Screenshot],
        query: String,
        collectionNamesByScreenshotID: [UUID: [String]] = [:],
        detectedCodesByScreenshotID: [String: [DetectedCode]] = [:]
    ) -> [Screenshot] {
        let parsed = ParsedSearchQuery(rawQuery: query)
        guard !parsed.isEmpty else { return screenshots }
        return screenshots.filter { screenshot in
            matches(
                screenshot,
                parsed: parsed,
                collectionNames: collectionNamesByScreenshotID[screenshot.id, default: []],
                detectedCodes: detectedCodesByScreenshotID[screenshot.uuidString, default: []]
            )
        }
    }

    private func matches(
        _ screenshot: Screenshot,
        parsed: ParsedSearchQuery,
        collectionNames: [String],
        detectedCodes: [DetectedCode]
    ) -> Bool {
        if let favorite = parsed.isFavorite, screenshot.isFavorite != favorite { return false }
        if let trashed = parsed.isTrashed, screenshot.isTrashed != trashed { return false }

        if !parsed.tagFilters.isEmpty,
           !parsed.tagFilters.allSatisfy({ filter in screenshot.tags.contains { contains($0, filter) } }) {
            return false
        }

        if !parsed.collectionFilters.isEmpty,
           !parsed.collectionFilters.allSatisfy({ filter in collectionNames.contains { contains($0, filter) } }) {
            return false
        }

        if !parsed.typeFilters.isEmpty,
           !parsed.typeFilters.contains(where: { equals(screenshot.format, $0) }) {
            return false
        }

        if !parsed.sourceFilters.isEmpty {
            let sourceFields = [screenshot.libraryPath ?? "", screenshot.sourceApp ?? ""]
            if !parsed.sourceFilters.allSatisfy({ filter in sourceFields.contains { contains($0, filter) } }) {
                return false
            }
        }

        for dateFilter in parsed.dateFilters {
            if !dateFilter.matches(screenshot.createdAt) { return false }
        }

        for hasFilter in parsed.hasFilters {
            switch hasFilter {
            case .ocr:
                if !(screenshot.isOCRComplete && !screenshot.ocrSnippets.isEmpty) { return false }
            case .qr:
                if detectedCodes.isEmpty { return false }
            case .url:
                if !detectedCodes.contains(where: \.isURL) { return false }
            }
        }

        guard !parsed.textTerms.isEmpty else { return true }
        let searchable = [
            screenshot.name,
            screenshot.format,
            screenshot.tags.joined(separator: " "),
            screenshot.ocrSnippets.joined(separator: " "),
            collectionNames.joined(separator: " "),
            detectedCodes.map(\.payload).joined(separator: " "),
            screenshot.libraryPath ?? "",
            screenshot.sourceApp ?? ""
        ].joined(separator: " ")

        return parsed.textTerms.allSatisfy { contains(searchable, $0) }
    }

    private func contains(_ value: String, _ token: String) -> Bool {
        value.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func equals(_ value: String, _ token: String) -> Bool {
        value.compare(token, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

struct ParsedSearchQuery: Hashable {
    enum HasFilter: String, Hashable {
        case ocr, qr, url
    }

    enum DateFilter: Hashable {
        case today
        case thisWeek

        func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
            switch self {
            case .today:
                return calendar.isDateInToday(date)
            case .thisWeek:
                return date >= Date().addingTimeInterval(-7 * 24 * 60 * 60)
            }
        }
    }

    let textTerms: [String]
    let tagFilters: [String]
    let collectionFilters: [String]
    let hasFilters: Set<HasFilter>
    let isFavorite: Bool?
    let isTrashed: Bool?
    let sourceFilters: [String]
    let typeFilters: [String]
    let dateFilters: [DateFilter]

    var isEmpty: Bool {
        textTerms.isEmpty &&
        tagFilters.isEmpty &&
        collectionFilters.isEmpty &&
        hasFilters.isEmpty &&
        isFavorite == nil &&
        isTrashed == nil &&
        sourceFilters.isEmpty &&
        typeFilters.isEmpty &&
        dateFilters.isEmpty
    }

    var includesTrashedScope: Bool {
        isTrashed == true
    }

    init(rawQuery: String) {
        var textTerms: [String] = []
        var tagFilters: [String] = []
        var collectionFilters: [String] = []
        var hasFilters: Set<HasFilter> = []
        var isFavorite: Bool?
        var isTrashed: Bool?
        var sourceFilters: [String] = []
        var typeFilters: [String] = []
        var dateFilters: [DateFilter] = []

        for rawToken in rawQuery.split(whereSeparator: \.isWhitespace).map(String.init) {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            let lower = token.lowercased()

            if let value = Self.value(after: "tag:", in: token) {
                tagFilters.append(value)
            } else if let value = Self.value(after: "collection:", in: token) {
                collectionFilters.append(value)
            } else if let value = Self.value(after: "has:", in: lower), let filter = HasFilter(rawValue: value) {
                hasFilters.insert(filter)
            } else if let value = Self.value(after: "is:", in: lower) {
                switch value {
                case "favorite", "favourite":
                    isFavorite = true
                case "trashed", "trash":
                    isTrashed = true
                default:
                    textTerms.append(token)
                }
            } else if let value = Self.value(after: "source:", in: token) {
                sourceFilters.append(value)
            } else if let value = Self.value(after: "type:", in: token) {
                typeFilters.append(value)
            } else if let value = Self.value(after: "date:", in: lower) {
                switch value {
                case "today":
                    dateFilters.append(.today)
                case "this-week", "thisweek", "week":
                    dateFilters.append(.thisWeek)
                default:
                    textTerms.append(token)
                }
            } else {
                textTerms.append(token)
            }
        }

        self.textTerms = textTerms
        self.tagFilters = tagFilters
        self.collectionFilters = collectionFilters
        self.hasFilters = hasFilters
        self.isFavorite = isFavorite
        self.isTrashed = isTrashed
        self.sourceFilters = sourceFilters
        self.typeFilters = typeFilters
        self.dateFilters = dateFilters
    }

    private static func value(after prefix: String, in token: String) -> String? {
        guard token.lowercased().hasPrefix(prefix) else { return nil }
        let value = String(token.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
