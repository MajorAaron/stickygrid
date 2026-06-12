import Foundation
import Testing
@testable import StickyGridCore

@Suite("Markdown typing — inline scanner")
struct InlineMatchTests {

    /// Caret at end of string, as if the last character was just typed.
    private func match(_ s: String) -> MarkdownTyping.InlineMatch? {
        MarkdownTyping.inlineMatch(paragraph: s, caret: (s as NSString).length)
    }

    @Test("**bold** matches bold with marker-free content range")
    func bold() throws {
        let m = try #require(match("**bold**"))
        #expect(m.style == .bold)
        #expect(m.fullRange == NSRange(location: 0, length: 8))
        #expect(m.contentRange == NSRange(location: 2, length: 4))
    }

    @Test("*italic* matches italic")
    func italic() throws {
        let m = try #require(match("*italic*"))
        #expect(m.style == .italic)
        #expect(m.fullRange == NSRange(location: 0, length: 8))
        #expect(m.contentRange == NSRange(location: 1, length: 6))
    }

    @Test("~~strike~~ matches strikethrough")
    func strike() throws {
        let m = try #require(match("~~strike~~"))
        #expect(m.style == .strikethrough)
        #expect(m.contentRange == NSRange(location: 2, length: 6))
    }

    @Test("`code` matches code")
    func code() throws {
        let m = try #require(match("`code`"))
        #expect(m.style == .code)
        #expect(m.contentRange == NSRange(location: 1, length: 4))
    }

    @Test("pattern mid-paragraph: ranges are offset, prior text untouched")
    func midParagraph() throws {
        let m = try #require(match("see **this**"))
        #expect(m.style == .bold)
        #expect(m.fullRange == NSRange(location: 4, length: 8))
        #expect(m.contentRange == NSRange(location: 6, length: 4))
    }

    @Test("only text before the caret is scanned")
    func caretBound() {
        // Caret sits right after "**bold**"; trailing text is ignored.
        let s = "**bold** and more"
        let m = MarkdownTyping.inlineMatch(paragraph: s, caret: 8)
        #expect(m?.style == .bold)
        // Caret one character earlier: closer incomplete, no match.
        #expect(MarkdownTyping.inlineMatch(paragraph: s, caret: 7) == nil)
    }

    @Test("longest delimiter wins: ** is bold, not italic around a star")
    func longestWins() throws {
        #expect(try #require(match("**bold**")).style == .bold)
    }

    @Test("space directly inside the markers blocks conversion")
    func innerSpace() {
        #expect(match("** bold**") == nil)
        #expect(match("**bold **") == nil)
        #expect(match("* italic*") == nil)
    }

    @Test("empty content blocks conversion")
    func emptyContent() {
        #expect(match("****") == nil)
        #expect(match("``") == nil)
    }

    @Test("opener glued to a word or digit blocks conversion")
    func wordBoundary() {
        #expect(match("snake*case*") == nil)
        #expect(match("5*6*") == nil)
    }

    @Test("opener after punctuation or whitespace converts")
    func punctuationBoundary() {
        #expect(match("(*hi*")?.style == .italic)
        #expect(match("a *b*")?.style == .italic)
    }

    @Test("typing the second star of a closing ** never italicizes")
    func halfTypedBold() {
        // "**bold*" — one star short of closing; the single-star closer must
        // not pair with the tail of the opening "**".
        #expect(match("**bold*") == nil)
    }

    @Test("bold content may contain a single star")
    func boldWithInnerStar() throws {
        let m = try #require(match("**a*b**"))
        #expect(m.style == .bold)
        #expect(m.contentRange == NSRange(location: 2, length: 3))
    }

    @Test("no delimiter at the caret: no match")
    func noDelimiter() {
        #expect(match("plain text") == nil)
        #expect(match("*italic") == nil)
    }
}
