import AppKit
import Testing
@testable import StickyGridApp

@MainActor
private func makeNote(text: String = "") -> (StickyTextView, RichTextController) {
    let tv = StickyTextView(usingTextLayoutManager: false)
    tv.isRichText = true
    let font = NSFont(name: "Helvetica Neue", size: 14)!
    tv.typingAttributes = [.font: font]
    tv.bodyFont = font
    if !text.isEmpty {
        tv.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        tv.restyleHeader()
    }
    let controller = RichTextController()
    controller.textView = tv
    return (tv, controller)
}

@MainActor
private func font(in tv: StickyTextView, at location: Int) -> NSFont {
    tv.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont
}

private func isBold(_ font: NSFont) -> Bool {
    NSFontManager.shared.traits(of: font).contains(.boldFontMask)
}

@MainActor
private final class UndoHost: NSObject, NSTextViewDelegate {
    let undo = UndoManager()
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
}

@Suite("Suggested title insertion")
@MainActor
struct TitleInsertTests {

    @Test("title becomes the new first line; old text shifts down intact")
    func insertAboveExistingText() {
        let (tv, controller) = makeNote(text: "milk\neggs")
        controller.insertTitleLine("Groceries")
        #expect(tv.string == "Groceries\nmilk\neggs")
    }

    @Test("new line is the header; old first line demotes to body size")
    func headerPromotion() {
        let (tv, controller) = makeNote(text: "milk\neggs")
        controller.insertTitleLine("Groceries")
        let header = font(in: tv, at: 0)
        #expect(header.pointSize == 18) // round(14 * 1.3)
        #expect(isBold(header))
        let demoted = font(in: tv, at: 10) // "milk"
        #expect(demoted.pointSize == 14)
        #expect(isBold(demoted)) // traits survive demotion (HeaderStylingTests invariant)
    }

    @Test("inserting into an empty note leaves just the title line")
    func emptyNote() {
        let (tv, controller) = makeNote()
        controller.insertTitleLine("Groceries")
        #expect(tv.string == "Groceries\n")
    }

    @Test("one undo removes the inserted title")
    func undo() {
        let (tv, controller) = makeNote(text: "milk")
        let host = UndoHost()
        tv.delegate = host
        tv.allowsUndo = true
        controller.insertTitleLine("Groceries")
        #expect(tv.string == "Groceries\nmilk")
        host.undo.undo()
        #expect(tv.string == "milk")
    }
}
