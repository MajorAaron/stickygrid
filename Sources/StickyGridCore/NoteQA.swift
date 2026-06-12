import Foundation

/// Corpus and prompt assembly for Ask Your Notes — the AI Q&A that reads
/// every note and answers as a new note. Pure string work; the app glue
/// gathers live note markdown and sends the request.
public enum NoteQA {

    /// One note as the model sees it.
    public struct Source: Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let body: String

        public init(id: UUID, title: String, body: String) {
            self.id = id
            self.title = title
            self.body = body
        }
    }

    /// Per-note character cap; keeps the corpus inside the request budget
    /// without token-exact accounting.
    public static let bodyLimit = 4000

    /// The notes the model reads, in list order (pinned first, then
    /// frontmost). Notes whose body closure returns nil or whitespace
    /// (empty notes) drop out; long bodies are truncated with a marker.
    public static func sources(
        for records: [NoteRecord], body: (UUID) -> String?
    ) -> [Source] {
        NoteListing.sorted(records).compactMap { record in
            guard let text = body(record.id),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return Source(
                id: record.id,
                title: record.titleSnippet.isEmpty ? "Untitled" : record.titleSnippet,
                body: truncated(text))
        }
    }

    static func truncated(_ body: String, limit: Int = bodyLimit) -> String {
        guard body.count > limit else { return body }
        return body.prefix(limit) + "\n…"
    }

    /// One section per source: title, the deep link the model cites, body.
    public static func context(for sources: [Source]) -> String {
        sources.map { source in
            """
            ## \(source.title)
            Link: stickygrid://open?note=\(source.id.uuidString.lowercased())

            \(source.body)
            """
        }
        .joined(separator: "\n\n")
    }

    public static func userMessage(question: String, context: String) -> String {
        """
        Question: \(question)

        Notes:

        \(context)
        """
    }

    public static var systemPrompt: String {
        """
        You answer the owner's question using only their sticky notes, \
        provided in the user message. Each note section gives its title, \
        its stickygrid:// link, and its text.

        Reply in markdown: a concise answer first, with "- " bullets where \
        they help scanning. Then a final "Sources" section listing the \
        stickygrid:// link of each note you actually used, one per line as \
        a bare URL — never wrap links in [text](url) syntax, because only \
        bare URLs are clickable in notes.

        If the notes do not answer the question, say so briefly and skip \
        the Sources section. Never invent note content or links.
        """
    }

    /// The answer note's markdown: the question collapsed to one heading
    /// line, then the model's answer verbatim.
    public static func answerMarkdown(question: String, answer: String) -> String {
        let title = question
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "# \(title)\n\n\(answer)"
    }
}
