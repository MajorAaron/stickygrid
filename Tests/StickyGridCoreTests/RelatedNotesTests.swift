import Foundation
import Testing
@testable import StickyGridCore

@Suite("Related notes — reply parsing and prompt assembly")
struct RelatedNotesTests {

    let a = UUID()
    let b = UUID()
    let c = UUID()

    func link(_ id: UUID) -> String {
        "stickygrid://open?note=\(id.uuidString.lowercased())"
    }

    // MARK: ids(fromReply:valid:) — the trust boundary

    @Test("cited ids come back in reply order")
    func replyOrder() {
        let reply = "\(link(b))\n\(link(a))"
        #expect(NoteRelated.ids(fromReply: reply, valid: [a, b, c]) == [b, a])
    }

    @Test("links not in the corpus are dropped")
    func unknownDropped() {
        let reply = "\(link(a))\n\(link(UUID()))\n\(link(b))"
        #expect(NoteRelated.ids(fromReply: reply, valid: [a, b]) == [a, b])
    }

    @Test("malformed note queries are dropped")
    func malformedDropped() {
        let reply = "stickygrid://open?note=not-a-uuid\n\(link(a))"
        #expect(NoteRelated.ids(fromReply: reply, valid: [a]) == [a])
    }

    @Test("duplicate citations collapse to the first mention")
    func deduped() {
        let reply = "\(link(a))\n\(link(b))\n\(link(a))"
        #expect(NoteRelated.ids(fromReply: reply, valid: [a, b]) == [a, b])
    }

    @Test("citations are capped at maxLinks")
    func capped() {
        let ids = (0..<8).map { _ in UUID() }
        let reply = ids.map(link).joined(separator: "\n")
        let parsed = NoteRelated.ids(fromReply: reply, valid: Set(ids))
        #expect(parsed == Array(ids.prefix(NoteRelated.maxLinks)))
    }

    @Test("NONE and link-free prose parse to no ids")
    func none() {
        #expect(NoteRelated.ids(fromReply: "NONE", valid: [a]) == [])
        #expect(NoteRelated.ids(
            fromReply: "Nothing here is related, sorry.", valid: [a]) == [])
    }

    @Test("a markdown-wrapped link still extracts despite the prompt ban")
    func markdownWrapped() {
        let reply = "[Grocery run](\(link(a)))"
        #expect(NoteRelated.ids(fromReply: reply, valid: [a]) == [a])
    }

    @Test("links survive surrounding prose and bullets")
    func proseTolerant() {
        let reply = "- The plan note: \(link(a)).\nAlso see \(link(b))!"
        #expect(NoteRelated.ids(fromReply: reply, valid: [a, b]) == [a, b])
    }

    // MARK: relatedMarkdown(for:)

    @Test("related section is a title — link bullet per source")
    func sectionFormat() {
        let sources = [
            NoteQA.Source(id: a, title: "Trip Plan", body: "x"),
            NoteQA.Source(id: b, title: "Packing List", body: "y"),
        ]
        #expect(NoteRelated.relatedMarkdown(for: sources) == """
            Related:
            - Trip Plan — \(link(a))
            - Packing List — \(link(b))
            """)
    }

    @Test("no sources means no section")
    func emptySection() {
        #expect(NoteRelated.relatedMarkdown(for: []) == nil)
    }

    // MARK: prompts

    @Test("user message carries the note above the corpus context")
    func userMessage() {
        let message = NoteRelated.userMessage(
            title: "Trip Plan", body: "pack bags", context: "## Other\nstuff")
        #expect(message.contains("Trip Plan"))
        #expect(message.contains("pack bags"))
        #expect(message.contains("## Other"))
        let noteAt = message.range(of: "pack bags")!.lowerBound
        let corpusAt = message.range(of: "## Other")!.lowerBound
        #expect(noteAt < corpusAt)
    }

    @Test("long note bodies are truncated like the QA corpus")
    func truncates() {
        let long = String(repeating: "a", count: NoteQA.bodyLimit + 100)
        let message = NoteRelated.userMessage(title: "T", body: long, context: "")
        #expect(!message.contains(long))
        #expect(message.contains("…"))
    }

    @Test("system prompt pins the reply contract")
    func systemPrompt() {
        let prompt = NoteRelated.systemPrompt
        #expect(prompt.contains("stickygrid://"))
        #expect(prompt.contains("NONE"))
        #expect(prompt.contains("[text](url)"))   // the ban, spelled out
        #expect(prompt.contains("\(NoteRelated.maxLinks)"))
    }
}
