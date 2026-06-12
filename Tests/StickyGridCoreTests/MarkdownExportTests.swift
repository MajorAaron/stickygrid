import Foundation
import Testing
@testable import StickyGridCore

@Suite("Markdown export — serializer")
struct MarkdownExportTests {

    private typealias Run = MarkdownExport.Run

    private func plain(_ text: String) -> Run { Run(text: text) }

    @Test("plain title and body — title becomes an H1 heading")
    func titleHeading() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("Groceries")],
            [plain("buy things")],
        ])
        #expect(md == "# Groceries\nbuy things")
    }

    @Test("empty first paragraph gets no heading marker")
    func emptyTitle() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("")],
            [plain("body")],
        ])
        #expect(md == "\nbody")
    }

    @Test("bold run wraps in **")
    func bold() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [plain("a "), Run(text: "bold", bold: true), plain(" b")],
        ])
        #expect(md == "# T\na **bold** b")
    }

    @Test("italic, strikethrough, and code runs")
    func styles() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [Run(text: "it", italic: true)],
            [Run(text: "gone", strikethrough: true)],
            [Run(text: "let x", code: true)],
        ])
        #expect(md == "# T\n*it*\n~~gone~~\n`let x`")
    }

    @Test("quote lines emit > and strip the bar literal")
    func quote() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [plain(MarkdownTyping.LineMarker.quote.literal + "wise words")],
        ])
        #expect(md == "# T\n> wise words")
    }

    @Test("a quote on the first line exports as a quote, not an H1")
    func quoteFirstLine() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain(MarkdownTyping.LineMarker.quote.literal + "opening line")],
        ])
        #expect(md == "> opening line")
    }

    @Test("bold+italic wraps in ***")
    func boldItalic() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [Run(text: "both", bold: true, italic: true)],
        ])
        #expect(md == "# T\n***both***")
    }

    @Test("strikethrough goes outside bold")
    func strikeBold() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [Run(text: "x", bold: true, strikethrough: true)],
        ])
        #expect(md == "# T\n~~**x**~~")
    }

    @Test("code wins over other flags")
    func codeWins() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [Run(text: "x", bold: true, code: true)],
        ])
        #expect(md == "# T\n`x`")
    }

    @Test("adjacent same-style runs merge into one delimiter pair")
    func merge() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [Run(text: "bo", bold: true), Run(text: "ld", bold: true)],
        ])
        #expect(md == "# T\n**bold**")
    }

    @Test("whitespace at styled-run edges is hoisted outside the delimiters")
    func whitespaceHoist() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [Run(text: " padded ", bold: true), plain("after")],
        ])
        #expect(md == "# T\n **padded** after")
    }

    @Test("whitespace-only styled run emits as plain whitespace")
    func whitespaceOnly() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [Run(text: "a", bold: true), Run(text: " ", bold: true),
             Run(text: "b", italic: true)],
        ])
        #expect(md == "# T\n**a** *b*")
    }

    @Test("bullet marker reverses to - ")
    func bullet() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [plain("\u{2022}\tmilk")],
        ])
        #expect(md == "# T\n- milk")
    }

    @Test("numbered marker keeps its number")
    func numbered() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [plain("1.\tfirst")],
            [plain("2.\tsecond")],
        ])
        #expect(md == "# T\n1. first\n2. second")
    }

    @Test("checkboxes reverse to - [ ] and - [x]")
    func checkboxes() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [plain("\u{2610}\topen")],
            [plain("\u{2611}\tdone")],
        ])
        #expect(md == "# T\n- [ ] open\n- [x] done")
    }

    @Test("styled text inside a list item keeps both marker and style")
    func styledListItem() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [plain("\u{2022}\t"), Run(text: "hot", bold: true)],
        ])
        #expect(md == "# T\n- **hot**")
    }

    @Test("marker split across the first styled run still reverses")
    func markerInsideStyledRun() {
        // The whole line, marker included, carries one style.
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [Run(text: "\u{2022}\tall bold", bold: true)],
        ])
        #expect(md == "# T\n- **all bold**")
    }

    @Test("a first line that is a list stays a list, not a heading")
    func listTitle() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("\u{2022}\titem")],
        ])
        #expect(md == "- item")
    }

    @Test("empty paragraphs between content are preserved")
    func blankLines() {
        let md = MarkdownExport.markdown(paragraphs: [
            [plain("T")],
            [],
            [plain("body")],
        ])
        #expect(md == "# T\n\nbody")
    }
}
