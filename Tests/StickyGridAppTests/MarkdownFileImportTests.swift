import AppKit
import StickyGridCore
import Testing
@testable import StickyGridApp

/// Loads RTF into a fresh editor the way openWindow does, header restyle
/// included: the editor carries the record's font, like NoteViewModel does.
@MainActor
private func editor(loading rtf: Data,
                    font: NSFont = NSFont(name: "Helvetica Neue", size: 14)!) -> StickyTextView {
    let tv = StickyTextView(usingTextLayoutManager: false)
    tv.isRichText = true
    tv.typingAttributes = [.font: font]
    tv.bodyFont = font
    let controller = RichTextController()
    controller.textView = tv
    controller.loadRTF(rtf)
    return tv
}

@MainActor
private func traits(at location: Int, in tv: StickyTextView) -> NSFontTraitMask {
    let font = tv.textStorage!.attribute(.font, at: location,
                                         effectiveRange: nil) as! NSFont
    return NSFontManager.shared.traits(of: font)
}

@Suite("Markdown file import")
@MainActor
struct MarkdownFileImportTests {

    @Test("markdown file content renders to RTF with native markers and styles")
    func rendersStyledRTF() {
        let record = NoteRecord(frame: .zero)
        let imported = WindowManager.importedNote(
            fromMarkdown: "# Groceries\nget **milk**\n- bread\n- [x] jam",
            record: record)!
        let tv = editor(loading: imported.rtf)
        #expect(tv.string == "Groceries\nget milk\n\u{2022}\tbread\n\u{2611}\tjam")

        let milk = (tv.string as NSString).range(of: "milk").location
        #expect(traits(at: milk, in: tv).contains(.boldFontMask))
        #expect(!traits(at: milk - 4, in: tv).contains(.boldFontMask))
    }

    @Test("imported note round-trips back to the same markdown")
    func roundTrip() {
        let md = "# Plan\nship **it** now\n- review\n- [ ] merge\n1. first"
        let record = NoteRecord(frame: .zero)
        let imported = WindowManager.importedNote(fromMarkdown: md, record: record)!
        #expect(editor(loading: imported.rtf).markdownText() == md)
    }

    @Test("title snippet is the first converted line, markdown stripped")
    func titleSnippet() {
        let record = NoteRecord(frame: .zero)
        let imported = WindowManager.importedNote(
            fromMarkdown: "# **Big** Plans\nbody", record: record)!
        #expect(imported.titleSnippet == "Big Plans")
    }

    @Test("title snippet caps at 40 characters and skips blank lines")
    func titleSnippetCap() {
        let record = NoteRecord(frame: .zero)
        let long = String(repeating: "a", count: 60)
        let imported = WindowManager.importedNote(
            fromMarkdown: "\n\n" + long, record: record)!
        #expect(imported.titleSnippet == String(repeating: "a", count: 40))
    }

    @Test("whitespace-only content imports nothing")
    func blankContent() {
        let record = NoteRecord(frame: .zero)
        #expect(WindowManager.importedNote(fromMarkdown: "  \n\t\n", record: record) == nil)
    }

    @Test("the record's font family and size carry into the RTF")
    func recordFont() {
        let record = NoteRecord(frame: .zero, fontName: "Georgia", fontSize: 18)
        let imported = WindowManager.importedNote(
            fromMarkdown: "Title\nbody text", record: record)!
        let tv = editor(loading: imported.rtf,
                        font: NSFont(name: "Georgia", size: 18)!)
        let body = (tv.string as NSString).range(of: "body").location
        let font = tv.textStorage!.attribute(.font, at: body,
                                             effectiveRange: nil) as! NSFont
        #expect(font.familyName == "Georgia")
        #expect(font.pointSize == 18)
    }
}
