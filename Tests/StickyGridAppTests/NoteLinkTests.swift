import AppKit
import Testing
@testable import StickyGridApp
import StickyGridCore

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
private func linkValue(at location: Int, in tv: StickyTextView) -> URL? {
    tv.textStorage!.attribute(.link, at: location, effectiveRange: nil) as? URL
}

@Suite("Clickable note links")
@MainActor
struct NoteLinkTests {

    @Test("restyleLinks marks the URL range and nothing else")
    func appliesLinkAttribute() {
        let tv = makeNote()
        tv.string = "Title\nsee stickygrid://open?note=plan today"
        tv.restyleLinks()

        let range = (tv.string as NSString).range(of: "stickygrid://open?note=plan")
        #expect(linkValue(at: range.location, in: tv)
                == URL(string: "stickygrid://open?note=plan"))
        #expect(linkValue(at: NSMaxRange(range) - 1, in: tv) != nil)
        #expect(linkValue(at: range.location - 1, in: tv) == nil)
        #expect(linkValue(at: NSMaxRange(range), in: tv) == nil)
    }

    @Test("editing the URL away clears the stale link attribute")
    func clearsStaleLinks() {
        let tv = makeNote()
        tv.string = "Title\nhttps://x.test"
        tv.restyleLinks()
        let loc = (tv.string as NSString).range(of: "https").location
        #expect(linkValue(at: loc, in: tv) != nil)

        tv.string = "Title\nhttps x.test"
        tv.restyleLinks()
        #expect(linkValue(at: loc, in: tv) == nil)
    }

    @Test("typing into a note links as part of didChangeText")
    func linksOnEdit() {
        let tv = makeNote()
        tv.string = "Title\n"
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        tv.insertText("https://x.test", replacementRange: tv.selectedRange())
        let loc = (tv.string as NSString).range(of: "https").location
        #expect(linkValue(at: loc, in: tv) != nil)
    }

    @Test("clicking a stickygrid link routes the query in-process")
    func clickRoutesOpenRequest() {
        let viewModel = NoteViewModel(record: NoteRecord(frame: .zero))
        var opened: [String] = []
        viewModel.onOpenNoteLink = { opened.append($0) }
        let coordinator = RichTextEditor.Coordinator(viewModel: viewModel)
        let tv = makeNote()

        let handled = coordinator.textView(
            tv, clickedOnLink: URL(string: "stickygrid://open?note=plan")!, at: 0)
        #expect(handled)
        #expect(opened == ["plan"])
    }

    @Test("clicking a web link falls through to the default handler")
    func clickFallsThroughForWeb() {
        let viewModel = NoteViewModel(record: NoteRecord(frame: .zero))
        var opened: [String] = []
        viewModel.onOpenNoteLink = { opened.append($0) }
        let coordinator = RichTextEditor.Coordinator(viewModel: viewModel)
        let tv = makeNote()

        let handled = coordinator.textView(
            tv, clickedOnLink: URL(string: "https://x.test")!, at: 0)
        #expect(!handled)
        #expect(opened.isEmpty)
    }
}
