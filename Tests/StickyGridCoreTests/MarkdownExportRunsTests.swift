import Foundation
import Testing
@testable import StickyGridCore

// The walker is AppKit-free: classification is injected, so these tests
// drive it with a private attribute key instead of fonts.
private let styleKey = NSAttributedString.Key("test.style")

private func styled(_ pieces: [(String, MarkdownExport.Style)]) -> NSAttributedString {
    let out = NSMutableAttributedString()
    for (text, style) in pieces {
        out.append(NSAttributedString(string: text, attributes: [styleKey: style]))
    }
    return out
}

private func classify(_ attrs: [NSAttributedString.Key: Any]) -> MarkdownExport.Style {
    attrs[styleKey] as? MarkdownExport.Style ?? MarkdownExport.Style()
}

private func markdown(_ pieces: [(String, MarkdownExport.Style)]) -> String {
    MarkdownExport.markdown(of: styled(pieces), classify: classify)
}

@Suite("Markdown export — attributed-string walker")
struct MarkdownExportRunsTests {

    @Test("paragraphs split on newlines, first line is the H1 title")
    func paragraphSplit() {
        #expect(markdown([("Groceries\nget milk", .init())])
                == "# Groceries\nget milk")
    }

    @Test("first-paragraph bold is the auto-header style and is dropped")
    func titleBoldDropped() {
        #expect(markdown([("Groceries", .init(bold: true)),
                          ("\nget ", .init()),
                          ("milk", .init(bold: true))])
                == "# Groceries\nget **milk**")
    }

    @Test("italic, strikethrough, and code styles serialize mid-note")
    func styles() {
        #expect(markdown([("T\n", .init()),
                          ("old", .init(strikethrough: true)),
                          (" ", .init()),
                          ("let x", .init(code: true)),
                          (" ", .init()),
                          ("hi", .init(italic: true))])
                == "# T\n~~old~~ `let x` *hi*")
    }

    @Test("marker-literal lines convert to markdown list prefixes")
    func markers() {
        let note = "T\n\u{2022}\tbread\n\u{2610}\tjam\n\u{258E}\twise words"
        #expect(markdown([(note, .init())])
                == "# T\n- bread\n- [ ] jam\n> wise words")
    }

    @Test("empty input exports as empty string")
    func empty() {
        #expect(markdown([]) == "")
    }

    @Test("runs(of:) reports paragraph runs with classified flags")
    func runsShape() {
        let runs = MarkdownExport.runs(
            of: styled([("a\nb", .init()), ("c", .init(bold: true))]),
            classify: classify)
        #expect(runs == [[MarkdownExport.Run(text: "a")],
                         [MarkdownExport.Run(text: "b"),
                          MarkdownExport.Run(text: "c", bold: true)]])
    }
}
