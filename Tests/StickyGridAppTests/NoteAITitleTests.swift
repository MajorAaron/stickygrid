import Testing
@testable import StickyGridApp

@Suite("AI title reply sanitizer")
@MainActor
struct NoteAITitleTests {

    @Test("clean reply passes through")
    func passThrough() {
        #expect(NoteAI.sanitizedTitle("Grocery Run") == "Grocery Run")
    }

    @Test("surrounding quotes are stripped")
    func quotes() {
        #expect(NoteAI.sanitizedTitle("\"Grocery Run\"") == "Grocery Run")
        #expect(NoteAI.sanitizedTitle("“Grocery Run”") == "Grocery Run")
        #expect(NoteAI.sanitizedTitle("'Grocery Run'") == "Grocery Run")
        #expect(NoteAI.sanitizedTitle("‘Grocery Run’") == "Grocery Run")
    }

    @Test("leading markdown header markers are stripped")
    func markdownHeader() {
        #expect(NoteAI.sanitizedTitle("# Grocery Run") == "Grocery Run")
        #expect(NoteAI.sanitizedTitle("## Grocery Run") == "Grocery Run")
    }

    @Test("a leading Title: label is stripped case-insensitively")
    func titleLabel() {
        #expect(NoteAI.sanitizedTitle("Title: Grocery Run") == "Grocery Run")
        #expect(NoteAI.sanitizedTitle("title: Grocery Run") == "Grocery Run")
    }

    @Test("first non-empty line of a chatty reply wins")
    func firstLine() {
        let reply = "\nGrocery Run\n\nThis title captures the note's intent."
        #expect(NoteAI.sanitizedTitle(reply) == "Grocery Run")
    }

    @Test("trailing period is dropped")
    func trailingPeriod() {
        #expect(NoteAI.sanitizedTitle("Grocery Run.") == "Grocery Run")
    }

    @Test("internal whitespace collapses, ends are trimmed")
    func whitespace() {
        #expect(NoteAI.sanitizedTitle("  Grocery   Run\t ") == "Grocery Run")
    }

    @Test("cleanup steps compose")
    func composed() {
        #expect(NoteAI.sanitizedTitle("# “Grocery  Run.”") == "Grocery Run")
    }

    @Test("empty and whitespace-only replies are nil")
    func empty() {
        #expect(NoteAI.sanitizedTitle("") == nil)
        #expect(NoteAI.sanitizedTitle("  \n\t\n") == nil)
        #expect(NoteAI.sanitizedTitle("\"\"") == nil)
    }
}
