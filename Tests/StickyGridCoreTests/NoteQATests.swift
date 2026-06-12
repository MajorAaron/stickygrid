import Foundation
import Testing
@testable import StickyGridCore

@Suite("Ask Your Notes corpus and prompts")
struct NoteQATests {

    private func record(
        _ title: String, pinned: Bool = false, zOrder: Int = 0
    ) -> NoteRecord {
        var record = NoteRecord(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        record.titleSnippet = title
        record.pinned = pinned
        record.zOrder = zOrder
        return record
    }

    // MARK: sources

    @Test("sources come in list order: pinned first, then frontmost")
    func sourceOrdering() {
        let back = record("Back", zOrder: 2)
        let front = record("Front", zOrder: 0)
        let pinned = record("Pinned", pinned: true, zOrder: 9)
        let sources = NoteQA.sources(for: [back, front, pinned]) { _ in "body" }
        #expect(sources.map(\.title) == ["Pinned", "Front", "Back"])
    }

    @Test("empty and nil bodies are skipped; blank titles fall back to Untitled")
    func sourceSkipsAndFallback() {
        let kept = record("")
        let empty = record("Empty")
        let unreadable = record("Unreadable")
        let bodies: [UUID: String?] = [
            kept.id: "content", empty.id: "  \n ", unreadable.id: nil,
        ]
        let sources = NoteQA.sources(for: [kept, empty, unreadable]) { bodies[$0] ?? nil }
        #expect(sources.count == 1)
        #expect(sources[0].id == kept.id)
        #expect(sources[0].title == "Untitled")
        #expect(sources[0].body == "content")
    }

    @Test("long bodies are truncated at bodyLimit with an ellipsis marker")
    func sourceTruncation() {
        let note = record("Long")
        let body = String(repeating: "x", count: NoteQA.bodyLimit + 500)
        let sources = NoteQA.sources(for: [note]) { _ in body }
        #expect(sources[0].body.hasSuffix("…"))
        #expect(sources[0].body.count == NoteQA.bodyLimit + 2)  // "\n…" appended
        #expect(sources[0].body.hasPrefix("xxx"))
    }

    @Test("short bodies are passed through untouched")
    func sourceNoTruncation() {
        let note = record("Short")
        let sources = NoteQA.sources(for: [note]) { _ in "- a\n- b" }
        #expect(sources[0].body == "- a\n- b")
    }

    // MARK: context

    @Test("context gives each note a title section, deep link, and body")
    func contextFormat() {
        let note = record("Plan")
        let sources = NoteQA.sources(for: [note]) { _ in "do the thing" }
        let context = NoteQA.context(for: sources)
        let link = "stickygrid://open?note=\(note.id.uuidString.lowercased())"
        #expect(context.contains("## Plan\n"))
        #expect(context.contains("Link: \(link)\n"))
        #expect(context.contains("do the thing"))
    }

    // MARK: messages

    @Test("user message carries the question and the corpus")
    func userMessage() {
        let message = NoteQA.userMessage(question: "where is the key?",
                                         context: "## Notes corpus here")
        #expect(message.contains("where is the key?"))
        #expect(message.contains("## Notes corpus here"))
    }

    @Test("system prompt demands markdown, honesty, and bare stickygrid links")
    func systemPromptInvariants() {
        let prompt = NoteQA.systemPrompt
        #expect(prompt.contains("markdown"))
        #expect(prompt.contains("stickygrid://"))
        #expect(prompt.contains("bare"))
        #expect(prompt.contains("[text](url)"))
    }

    // MARK: answer note

    @Test("answer note opens with the question as a heading line")
    func answerMarkdown() {
        let markdown = NoteQA.answerMarkdown(question: "What is due Friday?",
                                             answer: "The report.\n\nSources:")
        #expect(markdown == "# What is due Friday?\n\nThe report.\n\nSources:")
    }

    @Test("multi-line questions collapse to a single title line")
    func answerMarkdownCollapsesQuestion() {
        let markdown = NoteQA.answerMarkdown(question: " What\nis  due\n",
                                             answer: "Nothing.")
        #expect(markdown == "# What is due\n\nNothing.")
    }
}
