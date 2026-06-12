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

@Suite("Markdown typing — list triggers")
struct ListTriggerTests {

    @Test("- and * with a space trigger a bullet")
    func bullet() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "- ") == .bullet)
        #expect(MarkdownTyping.listTrigger(linePrefix: "* ") == .bullet)
    }

    @Test("N. with a space triggers a numbered item keeping the typed number")
    func numbered() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "1. ") == .numbered(1))
        #expect(MarkdownTyping.listTrigger(linePrefix: "12. ") == .numbered(12))
    }

    @Test("[ ] and [x] forms trigger checkboxes")
    func checkbox() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "[ ] ") == .checkbox(checked: false))
        #expect(MarkdownTyping.listTrigger(linePrefix: "[] ") == .checkbox(checked: false))
        #expect(MarkdownTyping.listTrigger(linePrefix: "[x] ") == .checkbox(checked: true))
        #expect(MarkdownTyping.listTrigger(linePrefix: "[X] ") == .checkbox(checked: true))
    }

    @Test("> with a space triggers a quote")
    func quote() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "> ") == .quote)
        #expect(MarkdownTyping.listTrigger(linePrefix: ">") == nil)       // no space yet
        #expect(MarkdownTyping.listTrigger(linePrefix: ">  ") == nil)     // extra space
        #expect(MarkdownTyping.listTrigger(linePrefix: "x > ") == nil)    // mid-line
    }

    @Test("anything else does not trigger")
    func noTrigger() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "-") == nil)       // no space yet
        #expect(MarkdownTyping.listTrigger(linePrefix: "-  ") == nil)     // extra space
        #expect(MarkdownTyping.listTrigger(linePrefix: "a. ") == nil)     // not a number
        #expect(MarkdownTyping.listTrigger(linePrefix: "1.") == nil)      // no space yet
        #expect(MarkdownTyping.listTrigger(linePrefix: "x - ") == nil)    // mid-line
    }

    @Test("typing [ ] on a fresh bullet upgrades it to a checkbox")
    func upgrade() {
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "[ ] ") == .checkbox(checked: false))
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "[] ") == .checkbox(checked: false))
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "[x] ") == .checkbox(checked: true))
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "[ ]") == nil)
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "milk ") == nil)
    }
}

@Suite("Markdown typing — line markers")
struct LineMarkerTests {

    @Test("literals for each marker kind")
    func literals() {
        #expect(MarkdownTyping.LineMarker.bullet.literal == "\u{2022}\t")
        #expect(MarkdownTyping.LineMarker.numbered(7).literal == "7.\t")
        #expect(MarkdownTyping.LineMarker.checkbox(checked: false).literal == "\u{2610}\t")
        #expect(MarkdownTyping.LineMarker.checkbox(checked: true).literal == "\u{2611}\t")
        #expect(MarkdownTyping.LineMarker.quote.literal == "\u{258E}\t")
    }

    @Test("parse recognizes each marker at paragraph start")
    func parse() {
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "\u{2022}\tmilk") == .bullet)
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "12.\tdo it") == .numbered(12))
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "\u{2610}\ttask")
                == .checkbox(checked: false))
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "\u{2611}\tdone")
                == .checkbox(checked: true))
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "\u{258E}\twise words") == .quote)
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "plain line") == nil)
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "1月\tx") == nil)
    }

    @Test("continuation: bullet repeats, numbers increment, checkboxes reset")
    func continuation() {
        #expect(MarkdownTyping.LineMarker.bullet.continuationLiteral == "\u{2022}\t")
        #expect(MarkdownTyping.LineMarker.numbered(7).continuationLiteral == "8.\t")
        #expect(MarkdownTyping.LineMarker.checkbox(checked: true).continuationLiteral
                == "\u{2610}\t")
        #expect(MarkdownTyping.LineMarker.quote.continuationLiteral == "\u{258E}\t")
    }
}
