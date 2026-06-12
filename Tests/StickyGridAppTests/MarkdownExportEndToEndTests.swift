import AppKit
import Testing
@testable import StickyGridApp

@MainActor
private func makeNote() -> StickyTextView {
    let tv = StickyTextView(usingTextLayoutManager: false)
    tv.isRichText = true
    let font = NSFont(name: "Helvetica Neue", size: 14)!
    tv.typingAttributes = [.font: font]
    tv.bodyFont = font
    return tv
}

/// Simulates typing: one insertText per character, return key via
/// insertNewline — the same paths real keystrokes take.
@MainActor
private func type(_ text: String, into tv: StickyTextView) {
    for ch in text {
        if ch == "\n" {
            tv.insertNewline(nil)
        } else {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
        }
    }
}

@Suite("Markdown export — end to end")
@MainActor
struct MarkdownExportEndToEndTests {

    @Test("typed note round-trips to markdown, auto-header bold dropped")
    func roundTrip() {
        let tv = makeNote()
        type("Groceries\nget **milk** now\n- bread\n[ ] jam", into: tv)
        #expect(tv.markdownText() == """
            # Groceries
            get **milk** now
            - bread
            - [ ] jam
            """)
    }

    @Test("strike and code spans serialize")
    func strikeAndCode() {
        let tv = makeNote()
        type("T\n~~old~~ `let x`", into: tv)
        #expect(tv.markdownText() == "# T\n~~old~~ `let x`")
    }

    @Test("user italic in the title survives, auto-bold does not")
    func titleStyles() {
        let tv = makeNote()
        type("a *b* c", into: tv)
        #expect(tv.markdownText() == "# a *b* c")
    }

    @Test("empty note exports as empty string")
    func empty() {
        let tv = makeNote()
        #expect(tv.markdownText() == "")
    }

    @Test("numbered list and checked checkbox")
    func lists() {
        let tv = makeNote()
        type("T\n1. one\ntwo", into: tv)
        // Return after "one" auto-continues with "2.\t".
        #expect(tv.markdownText() == "# T\n1. one\n2. two")
    }
}

@Suite("Export file name")
struct ExportFileNameTests {

    @Test("first line, sanitized, .md appended")
    func sanitizes() {
        #expect(WindowManager.exportFileName(title: "a/b: c\nrest") == "a-b- c.md")
    }

    @Test("empty title falls back to Note.md")
    func fallback() {
        #expect(WindowManager.exportFileName(title: "  \n ") == "Note.md")
    }
}
