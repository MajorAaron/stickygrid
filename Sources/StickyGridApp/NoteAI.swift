import Foundation
import StickyGridCore

extension NoteColor {
    /// Parses a model reply ("green", "Green.", "I'd pick blue because…")
    /// into a palette color. When several colors are named, the earliest
    /// mention wins. Accepts the "grey" spelling. Nil when no color is named.
    init?(aiReply: String) {
        let reply = aiReply.lowercased()
        let candidates: [(name: String, color: NoteColor)] =
            NoteColor.allCases.map { ($0.rawValue, $0) } + [("grey", .gray)]
        let earliest = candidates
            .compactMap { candidate in
                reply.range(of: candidate.name).map { (range: $0, color: candidate.color) }
            }
            .min { $0.range.lowerBound < $1.range.lowerBound }
        guard let earliest else { return nil }
        self = earliest.color
    }
}

/// One of the AI transforms a note's text can be run through.
enum NoteAIAction: Identifiable, Equatable {
    case summarize
    case checklist
    case polish
    /// A free-form instruction written by the user (Ask AI…).
    case ask(String)

    /// The fixed transforms shown in menus; `ask` is reached via its prompt UI.
    static let presets: [NoteAIAction] = [.summarize, .checklist, .polish]

    var id: String {
        switch self {
        case .summarize: "summarize"
        case .checklist: "checklist"
        case .polish: "polish"
        case .ask: "ask"
        }
    }

    var title: String {
        switch self {
        case .summarize: "Summarize"
        case .checklist: "Turn Into Checklist"
        case .polish: "Polish Writing"
        case .ask: "Ask AI"
        }
    }

    var systemPrompt: String {
        let shared = """
            You rewrite the text of a sticky note. The first line of a note is its \
            title. Return ONLY the new note text as plain text — no markdown \
            headers, no code fences, no commentary before or after.
            """
        switch self {
        case .summarize:
            return shared + """

                Condense the note to its essential points. Keep (or write) a short \
                first-line title, then short lines below it; use "- " bullets where \
                they help scanning.
                """
        case .checklist:
            return shared + """

                Convert the note into an actionable checklist. Keep (or write) a \
                short first-line title, then one task per line starting with "- ". \
                Keep every distinct item; split compound items into separate tasks.
                """
        case .polish:
            return shared + """

                Fix spelling, grammar, and awkward phrasing while preserving the \
                meaning, tone, line breaks, and overall structure. Keep the first \
                line as the title.
                """
        case .ask(let instruction):
            return shared + """

                Apply this instruction from the note's owner to the note text:

                \(instruction)

                If the instruction conflicts with the output format above, the \
                output format wins: always return only the rewritten note text.
                """
        }
    }
}

enum NoteAIError: LocalizedError {
    case missingKey
    case api(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Anthropic API key is set. Use AI → Set Anthropic API Key…, "
                + "or export ANTHROPIC_API_KEY before launching StickyGrid."
        case .api(let message):
            return message
        case .badResponse:
            return "The AI service returned an unexpected response."
        }
    }
}

/// Minimal Anthropic Messages API client for note transforms.
/// Key resolution: ANTHROPIC_API_KEY env var, then the key file written by
/// `saveKey` (~/.config/stickygrid/anthropic-api-key).
enum NoteAI {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let defaultModel = "claude-opus-4-8"

    static var keyFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/stickygrid/anthropic-api-key")
    }

    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !env.isEmpty {
            return env
        }
        guard let raw = try? String(contentsOf: keyFileURL, encoding: .utf8) else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static func saveKey(_ key: String) throws {
        let dir = keyFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try key.trimmingCharacters(in: .whitespacesAndNewlines)
            .write(to: keyFileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
    }

    // MARK: Request/response wire types

    private struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    private struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let message: String
        }
        let error: Detail
    }

    /// Runs the note text through the action's prompt and returns the new text.
    static func transform(_ text: String, action: NoteAIAction) async throws -> String {
        try await complete(system: action.systemPrompt, user: text)
    }

    /// Picks the palette color that best fits the note's content.
    static func suggestColor(for text: String) async throws -> NoteColor {
        let reply = try await complete(system: colorSystemPrompt, user: text)
        guard let color = NoteColor(aiReply: reply) else { throw NoteAIError.badResponse }
        return color
    }

    /// Answers a question from the whole-grid corpus (Ask Your Notes);
    /// the caller turns the markdown reply into a new note.
    static func answer(question: String, context: String) async throws -> String {
        try await complete(
            system: NoteQA.systemPrompt,
            user: NoteQA.userMessage(question: question, context: context))
    }

    /// Picks the notes related to the current one (Find Related Notes);
    /// the caller parses the reply's links with `NoteRelated.ids` and
    /// appends the Related section.
    static func relatedNotes(title: String, body: String, context: String) async throws -> String {
        try await complete(
            system: NoteRelated.systemPrompt,
            user: NoteRelated.userMessage(title: title, body: body, context: context))
    }

    /// Proposes a short title for the note; the caller inserts it as a new
    /// first line. Replies are normalized by `sanitizedTitle`.
    static func suggestTitle(for text: String) async throws -> String {
        let reply = try await complete(system: titleSystemPrompt, user: text)
        guard let title = sanitizedTitle(reply) else { throw NoteAIError.badResponse }
        return title
    }

    static var titleSystemPrompt: String {
        """
        You title sticky notes. Read the note text and reply with a short \
        title of 2–6 words that captures what the note is about.

        Reply with the title only, on a single line: no quotes, no markdown, \
        no trailing punctuation, no explanation.
        """
    }

    /// Normalizes a title reply: first non-empty line, minus a "Title:"
    /// label, markdown `#` markers, surrounding quotes, and a trailing
    /// period, with whitespace collapsed. Nil when nothing is left —
    /// models drift from "title only" instructions the same way the color
    /// parser's models drift from "one word".
    static func sanitizedTitle(_ reply: String) -> String? {
        let line = reply
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard var title = line else { return nil }

        title = title.trimmingCharacters(in: .whitespaces)
        let label = /^title:\s*/.ignoresCase()
        title.replace(label, with: "", maxReplacements: 1)
        while title.hasPrefix("#") { title.removeFirst() }
        let quotes = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}")
        title = title.trimmingCharacters(in: quotes.union(.whitespaces))
        while title.hasSuffix(".") { title.removeLast() }
        title = title
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return title.isEmpty ? nil : title
    }

    /// Built from `NoteColor.allCases` so a new palette color can't be forgotten.
    static var colorSystemPrompt: String {
        let names = NoteColor.allCases.map(\.rawValue).joined(separator: ", ")
        return """
            You assign a sticky-note color based on the note's text. The \
            available colors are: \(names).

            Guidance: yellow for general notes, pink for personal or fun, \
            blue for reference or technical, green for shopping or money or \
            done-ness, purple for ideas and creative work, orange for urgent \
            or deadline-driven, gray for archival or low-priority, white for \
            drafts and plain documents.

            Reply with exactly one word: the color name. No punctuation, no \
            explanation.
            """
    }

    /// One Messages-API round trip: system prompt + user text → reply text.
    private static func complete(system: String, user: String) async throws -> String {
        guard let key = apiKey() else { throw NoteAIError.missingKey }

        let model = UserDefaults.standard.string(forKey: "AIModel") ?? defaultModel
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(Request(
            model: model,
            max_tokens: 16000,
            system: system,
            messages: [.init(role: "user", content: user)]))

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw NoteAIError.api(envelope.error.message)
            }
            throw NoteAIError.api("AI request failed (HTTP \(http.statusCode)).")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let result = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw NoteAIError.badResponse }
        return result
    }
}
