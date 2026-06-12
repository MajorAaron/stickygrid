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

@MainActor
private func traits(at location: Int, in tv: StickyTextView) -> NSFontTraitMask {
    let font = tv.textStorage!.attribute(.font, at: location,
                                         effectiveRange: nil) as! NSFont
    return NSFontManager.shared.traits(of: font)
}

@Suite("Markdown paste — end to end")
@MainActor
struct MarkdownPasteTests {

    @Test("pasted markdown converts styles and list markers")
    func convertsOnInsert() {
        let tv = makeNote()
        tv.insertMarkdown("Title\nget **milk**\n- bread\n- [x] jam")
        #expect(tv.string == "Title\nget milk\n\u{2022}\tbread\n\u{2611}\tjam")

        // "milk" on line 2 is bold; "get " is not.
        let line2 = (tv.string as NSString).range(of: "get milk").location
        #expect(!traits(at: line2, in: tv).contains(.boldFontMask))
        #expect(traits(at: line2 + 4, in: tv).contains(.boldFontMask))
    }

    @Test("pasted note round-trips back to the same markdown")
    func roundTrip() {
        let md = "# Groceries\nget **milk** now\n- bread\n- [ ] jam\n1. first"
        let tv = makeNote()
        tv.insertMarkdown(md)
        #expect(tv.markdownText() == md)
    }

    @Test("code spans get the code font at body size")
    func codeFont() {
        let tv = makeNote()
        tv.insertMarkdown("T\nrun `swift test` now")
        let loc = (tv.string as NSString).range(of: "swift test").location
        let font = tv.textStorage!.attribute(.font, at: loc,
                                             effectiveRange: nil) as! NSFont
        #expect(font.fontName.hasPrefix(StickyTextView.codeFontName))
        #expect(font.pointSize == 14)
    }

    @Test("pasted list lines continue on return like typed ones")
    func listContinuation() {
        let tv = makeNote()
        tv.insertMarkdown("T\n1. one")
        tv.insertNewline(nil)
        tv.insertText("two", replacementRange: tv.selectedRange())
        #expect(tv.string == "T\n1.\tone\n2.\ttwo")
    }

    @Test("first heading line becomes the auto-header, not double-bold body")
    func headerLine() {
        let tv = makeNote()
        tv.insertMarkdown("# Title\nbody")
        #expect(tv.string == "Title\nbody")
        let headerFont = tv.textStorage!.attribute(.font, at: 0,
                                                   effectiveRange: nil) as! NSFont
        #expect(headerFont.pointSize == (14 * StickyTextView.headerScale).rounded())
    }

    @Test("insert lands at the caret and replaces the selection")
    func replacesSelection() {
        let tv = makeNote()
        tv.insertText("T\nab", replacementRange: tv.selectedRange())
        tv.setSelectedRange(NSRange(location: 3, length: 1))  // select "b"
        tv.insertMarkdown("**x**")
        #expect(tv.string == "T\nax")
    }

    @Test("one undo restores the pre-paste text")
    func undo() {
        let tv = makeNote()
        let host = UndoHost()
        tv.delegate = host
        tv.allowsUndo = true
        tv.insertText("T", replacementRange: tv.selectedRange())
        host.undo.removeAllActions()
        tv.insertMarkdown("\n- **x**")
        #expect(tv.string == "T\n\u{2022}\tx")
        host.undo.undo()
        #expect(tv.string == "T")
    }
}

@MainActor
private final class UndoHost: NSObject, NSTextViewDelegate {
    let undo = UndoManager()
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
}
