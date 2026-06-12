import Foundation

/// Pure search logic behind Find in Notes (⌘F): case- and diacritic-
/// insensitive substring search across every note's plain text.
public enum NoteSearch {
    /// One note's searchable content.
    public struct Source: Sendable {
        public let id: UUID
        public let text: String

        public init(id: UUID, text: String) {
            self.id = id
            self.text = text
        }
    }

    public struct Match: Equatable, Sendable, Identifiable {
        public let noteID: UUID
        /// First non-empty line of the note, trimmed (the note's de-facto title).
        public let title: String
        /// The matching line, windowed to at most `snippetLimit` characters.
        public let snippet: String
        /// UTF-16 offset of the first hit in the note's full text, for
        /// selecting the match in an NSTextView.
        public let matchLocation: Int
        public let matchLength: Int
        /// True when the hit falls inside the title line; ranked first.
        public let isTitleMatch: Bool

        public var id: UUID { noteID }
    }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private static let snippetLimit = 80

    /// Returns one match per note that contains `query`, title hits first,
    /// otherwise preserving the caller's note order (pass frontmost first).
    public static func search(query: String, in notes: [Source]) -> [Match] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let matches = notes.compactMap { match(query: query, in: $0) }
        return matches.filter(\.isTitleMatch) + matches.filter { !$0.isTitleMatch }
    }

    private static func match(query: String, in note: Source) -> Match? {
        let text = note.text
        guard let range = text.range(of: query, options: options) else { return nil }

        let title = firstNonEmptyLine(of: text) ?? "Untitled"

        let lineRange = text.lineRange(for: range)
        let line = text[lineRange].trimmingCharacters(in: .whitespacesAndNewlines)
        let nsRange = NSRange(range, in: text)

        return Match(
            noteID: note.id,
            title: String(title.prefix(60)),
            snippet: window(line: line, around: query),
            matchLocation: nsRange.location,
            matchLength: nsRange.length,
            isTitleMatch: firstNonEmptyLineRange(of: text).map { range.overlaps($0) } ?? false)
    }

    private static func firstNonEmptyLine(of text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    private static func firstNonEmptyLineRange(of text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex {
            let lineRange = text.lineRange(for: searchStart..<searchStart)
            if !text[lineRange].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lineRange
            }
            guard lineRange.upperBound > searchStart else { return nil }
            searchStart = lineRange.upperBound
        }
        return nil
    }

    /// Trims a long line to `snippetLimit` characters centered on the hit.
    private static func window(line: String, around query: String) -> String {
        guard line.count > snippetLimit else { return line }
        guard let hit = line.range(of: query, options: options) else {
            return String(line.prefix(snippetLimit - 1)) + "…"
        }

        let hitStart = line.distance(from: line.startIndex, to: hit.lowerBound)
        let hitLength = line.distance(from: hit.lowerBound, to: hit.upperBound)
        let room = max(0, snippetLimit - hitLength - 2)  // 2 for possible ellipses
        let start = max(0, hitStart - room / 2)
        let end = min(line.count, start + snippetLimit - 2)

        let lower = line.index(line.startIndex, offsetBy: start)
        let upper = line.index(line.startIndex, offsetBy: end)
        var snippet = String(line[lower..<upper])
        if start > 0 { snippet = "…" + snippet }
        if end < line.count { snippet += "…" }
        return snippet
    }
}
