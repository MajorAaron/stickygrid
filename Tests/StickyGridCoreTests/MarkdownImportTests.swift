import Foundation
import Testing
@testable import StickyGridCore

@Suite("Markdown import — parser")
struct MarkdownImportTests {

    private typealias Run = MarkdownExport.Run
    private typealias Line = MarkdownImport.Line

    private func plain(_ text: String) -> Run { Run(text: text) }

    @Test("plain text parses to unmarked plain lines")
    func plainText() {
        let lines = MarkdownImport.parse("hello\nworld")
        #expect(lines == [
            Line(marker: nil, runs: [plain("hello")]),
            Line(marker: nil, runs: [plain("world")]),
        ])
    }

    @Test("bold, italic, strike, and code spans")
    func inlineStyles() {
        let lines = MarkdownImport.parse("a **b** *c* ~~d~~ `e`")
        #expect(lines == [
            Line(marker: nil, runs: [
                plain("a "), Run(text: "b", bold: true),
                plain(" "), Run(text: "c", italic: true),
                plain(" "), Run(text: "d", strikethrough: true),
                plain(" "), Run(text: "e", code: true),
            ]),
        ])
    }

    @Test("*** is bold+italic")
    func boldItalic() {
        let lines = MarkdownImport.parse("***both***")
        #expect(lines == [
            Line(marker: nil, runs: [Run(text: "both", bold: true, italic: true)]),
        ])
    }

    @Test("strike nests over bold, matching export's ~~**x**~~ shape")
    func nestedStrikeBold() {
        let lines = MarkdownImport.parse("~~**x**~~")
        #expect(lines == [
            Line(marker: nil, runs: [Run(text: "x", bold: true, strikethrough: true)]),
        ])
    }

    @Test("code content stays literal — markup inside is not parsed")
    func codeLiteral() {
        let lines = MarkdownImport.parse("`a **b**`")
        #expect(lines == [
            Line(marker: nil, runs: [Run(text: "a **b**", code: true)]),
        ])
    }

    @Test("unmatched and whitespace-padded delimiters stay literal")
    func invalidDelimiters() {
        #expect(MarkdownImport.parse("*foo") ==
                [Line(marker: nil, runs: [plain("*foo")])])
        #expect(MarkdownImport.parse("x * foo *") ==
                [Line(marker: nil, runs: [plain("x * foo *")])])
        #expect(MarkdownImport.parse("a*b*c") ==
                [Line(marker: nil, runs: [plain("a*b*c")])])
    }

    @Test("list markers map to the native line markers")
    func listMarkers() {
        let lines = MarkdownImport.parse("- a\n* b\n3. c")
        #expect(lines == [
            Line(marker: .bullet, runs: [plain("a")]),
            Line(marker: .bullet, runs: [plain("b")]),
            Line(marker: .numbered(3), runs: [plain("c")]),
        ])
    }

    @Test("checkboxes, checked and unchecked, either bullet, case-insensitive")
    func checkboxes() {
        let lines = MarkdownImport.parse("- [ ] open\n- [x] done\n* [X] also")
        #expect(lines == [
            Line(marker: .checkbox(checked: false), runs: [plain("open")]),
            Line(marker: .checkbox(checked: true), runs: [plain("done")]),
            Line(marker: .checkbox(checked: true), runs: [plain("also")]),
        ])
    }

    @Test("styled text inside a list item")
    func styledListItem() {
        let lines = MarkdownImport.parse("- **hot**")
        #expect(lines == [
            Line(marker: .bullet, runs: [Run(text: "hot", bold: true)]),
        ])
    }

    @Test("headings strip the #s and render bold")
    func headings() {
        let lines = MarkdownImport.parse("# Title\n### Sub *it*")
        #expect(lines == [
            Line(marker: nil, runs: [Run(text: "Title", bold: true)]),
            Line(marker: nil, runs: [
                Run(text: "Sub ", bold: true),
                Run(text: "it", bold: true, italic: true),
            ]),
        ])
    }

    @Test("a # without a space is not a heading")
    func hashNoSpace() {
        #expect(MarkdownImport.parse("#tag") ==
                [Line(marker: nil, runs: [plain("#tag")])])
    }

    @Test("blank lines survive as empty lines")
    func blankLines() {
        let lines = MarkdownImport.parse("a\n\nb")
        #expect(lines == [
            Line(marker: nil, runs: [plain("a")]),
            Line(marker: nil, runs: []),
            Line(marker: nil, runs: [plain("b")]),
        ])
    }

    @Test("detection: styled or marked text is markdown, plain text is not")
    func detection() {
        #expect(MarkdownImport.detectsMarkdown("get **milk**"))
        #expect(MarkdownImport.detectsMarkdown("- bread"))
        #expect(MarkdownImport.detectsMarkdown("# Title"))
        #expect(!MarkdownImport.detectsMarkdown("just plain text"))
        #expect(!MarkdownImport.detectsMarkdown("2 * 3 = 6 and 4 * 2 = 8"))
        #expect(!MarkdownImport.detectsMarkdown(""))
    }

    @Test("export round-trips through import for body content")
    func roundTrip() {
        let md = "get **milk** and *jam*\n- bread\n1. first\n- [x] done\n`let x`"
        let lines = MarkdownImport.parse(md)
        let paragraphs = lines.map { line -> [Run] in
            guard let marker = line.marker else { return line.runs }
            return [Run(text: marker.literal)] + line.runs
        }
        // First line is plain body here, so Core's H1 rule would add "# " —
        // prepend a list line to keep the comparison exact.
        #expect(MarkdownExport.markdown(paragraphs:
            [[Run(text: MarkdownTyping.LineMarker.bullet.literal + "x")]] + paragraphs)
            == "- x\n" + md)
    }
}
