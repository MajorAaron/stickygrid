import AppKit
import Testing
import StickyGridCore
@testable import StickyGridApp

@MainActor
private func makeController() -> (RichTextController, StickyTextView) {
    let tv = StickyTextView(usingTextLayoutManager: false)
    tv.isRichText = true
    let font = NSFont(name: "Helvetica Neue", size: 14)!
    tv.typingAttributes = [.font: font]
    tv.bodyFont = font
    let controller = RichTextController()
    controller.textView = tv
    return (controller, tv)
}

@Suite("Related notes — append path and corpus rule")
@MainActor
struct RelatedAppendTests {

    let url = "stickygrid://open?note=4cc62d33-1f9b-4f4e-9241-0f55a4a4b202"

    @Test("appendMarkdown lands after the existing text with a blank line")
    func appendsAfterText() {
        let (controller, tv) = makeController()
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        #expect(tv.string == "T\nbody\n\nRelated:\n\u{2022}\tPlan — \(url)")
    }

    @Test("appendMarkdown on an empty note adds no separator")
    func appendsToEmpty() {
        let (controller, tv) = makeController()
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        #expect(tv.string == "Related:\n\u{2022}\tPlan — \(url)")
    }

    @Test("the appended deep link is clickable immediately")
    func linkRestyled() {
        let (controller, tv) = makeController()
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        let range = (tv.string as NSString).range(of: url)
        let value = tv.textStorage!.attribute(.link, at: range.location,
                                              effectiveRange: nil)
        #expect(value != nil)
    }

    @Test("one undo removes the whole appended section")
    func undo() {
        let (controller, tv) = makeController()
        let host = UndoHost()
        tv.delegate = host
        tv.allowsUndo = true
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        host.undo.removeAllActions()
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        host.undo.undo()
        #expect(tv.string == "T\nbody")
    }

    // MARK: replaceRelated — re-runs refresh instead of stacking

    let url2 = "stickygrid://open?note=9a1832c0-55c4-4d6a-8d3b-6a4f7f0a8f11"

    @Test("replaceRelated swaps the old section for the new one")
    func replacesOldSection() {
        let (controller, tv) = makeController()
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        controller.replaceRelated("Related:\n- List — \(url2)")
        #expect(tv.string == "T\nbody\n\nRelated:\n\u{2022}\tList — \(url2)")
    }

    @Test("replaceRelated without an existing section behaves like append")
    func replaceIsAppendWhenNoSection() {
        let (controller, tv) = makeController()
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        controller.replaceRelated("Related:\n- Plan — \(url)")
        #expect(tv.string == "T\nbody\n\nRelated:\n\u{2022}\tPlan — \(url)")
    }

    @Test("stacked duplicate sections collapse to the fresh one")
    func collapsesStackedSections() {
        let (controller, tv) = makeController()
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        controller.replaceRelated("Related:\n- List — \(url2)")
        #expect(tv.string == "T\nbody\n\nRelated:\n\u{2022}\tList — \(url2)")
    }

    @Test("user text typed after the section survives a replace")
    func keepsTrailingUserText() {
        let (controller, tv) = makeController()
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
        tv.insertText("\nps. keep me", replacementRange: tv.selectedRange())
        controller.replaceRelated("Related:\n- List — \(url2)")
        #expect(tv.string.contains("ps. keep me"))
        #expect(!tv.string.contains(url))
        #expect(tv.string.contains("Related:\n\u{2022}\tList — \(url2)"))
    }

    @Test("one undo reverts the whole replace")
    func undoRevertsReplace() {
        let (controller, tv) = makeController()
        let host = UndoHost()
        tv.delegate = host
        tv.allowsUndo = true
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        let before = tv.string
        host.undo.removeAllActions()
        controller.replaceRelated("Related:\n- List — \(url2)")
        host.undo.undo()
        #expect(tv.string == before)
    }

    @Test("the fresh section's deep link is clickable")
    func replacedLinkRestyled() {
        let (controller, tv) = makeController()
        tv.insertText("T\nbody", replacementRange: tv.selectedRange())
        controller.appendMarkdown("Related:\n- Plan — \(url)")
        controller.replaceRelated("Related:\n- List — \(url2)")
        let range = (tv.string as NSString).range(of: url2)
        let value = tv.textStorage!.attribute(.link, at: range.location,
                                              effectiveRange: nil)
        #expect(value != nil)
    }

    @Test("the related corpus is every other non-empty note")
    func corpusExcludesCurrent() {
        let current = NoteRecord(frame: .zero, titleSnippet: "Me")
        let other = NoteRecord(frame: .zero, titleSnippet: "Other")
        let empty = NoteRecord(frame: .zero, titleSnippet: "Empty")
        let bodies = [current.id: "mine", other.id: "theirs"]
        let sources = WindowManager.relatedSources(
            records: [current, other, empty],
            excluding: current.id) { bodies[$0] }
        #expect(sources.map(\.id) == [other.id])
    }
}

@MainActor
private final class UndoHost: NSObject, NSTextViewDelegate {
    let undo = UndoManager()
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
}
