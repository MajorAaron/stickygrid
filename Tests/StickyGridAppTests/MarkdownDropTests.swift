import AppKit
import StickyGridCore
import Testing
@testable import StickyGridApp

/// A unique scratch pasteboard per test, released when the test ends.
private func scratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("test-drop-\(UUID().uuidString)"))
}

/// Minimal NSDraggingInfo so performDragOperation can run headless.
private final class DragStub: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    init(pasteboard: NSPasteboard) { self.pasteboard = pasteboard }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions,
        for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@MainActor
private func editor() -> StickyTextView {
    let tv = StickyTextView(usingTextLayoutManager: false)
    tv.isRichText = true
    let font = NSFont(name: "Helvetica Neue", size: 14)!
    tv.typingAttributes = [.font: font]
    tv.bodyFont = font
    return tv
}

@Suite("Markdown drop classification")
@MainActor
struct DropActionTests {

    @Test("a dropped .md file maps to the file-import action")
    func mdFile() {
        let pb = scratchPasteboard()
        let url = URL(fileURLWithPath: "/tmp/groceries.md")
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        #expect(StickyTextView.dropAction(for: pb) == .importFiles([url]))
    }

    @Test("markdown extensions match case-insensitively")
    func caseInsensitiveExtension() {
        let pb = scratchPasteboard()
        let urls = [URL(fileURLWithPath: "/tmp/NOTES.MD"),
                    URL(fileURLWithPath: "/tmp/plan.Markdown")]
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
        #expect(StickyTextView.dropAction(for: pb) == .importFiles(urls))
    }

    @Test("a non-markdown file keeps default drop behavior")
    func nonMarkdownFile() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/tmp/photo.png") as NSURL])
        #expect(StickyTextView.dropAction(for: pb) == .passthrough)
    }

    @Test("a mixed drop imports only the markdown files")
    func mixedFiles() {
        let pb = scratchPasteboard()
        let md = URL(fileURLWithPath: "/tmp/plan.md")
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/tmp/photo.png") as NSURL,
                         md as NSURL])
        #expect(StickyTextView.dropAction(for: pb) == .importFiles([md]))
    }

    @Test("a file drag that also carries text still imports the file")
    func filePlusText() {
        let pb = scratchPasteboard()
        let md = URL(fileURLWithPath: "/tmp/plan.md")
        pb.clearContents()
        pb.writeObjects([md as NSURL, "**not** converted" as NSString])
        #expect(StickyTextView.dropAction(for: pb) == .importFiles([md]))
    }

    @Test("plain text containing markdown maps to styled insertion")
    func markdownText() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("get **milk**\n- bread", forType: .string)
        #expect(StickyTextView.dropAction(for: pb)
            == .insertMarkdown("get **milk**\n- bread"))
    }

    @Test("plain text without markdown keeps default drop behavior")
    func plainText() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("just words, no markers", forType: .string)
        #expect(StickyTextView.dropAction(for: pb) == .passthrough)
    }

    @Test("rich-text drags keep default drop behavior")
    func richText() {
        let pb = scratchPasteboard()
        pb.clearContents()
        let rtf = NSAttributedString(string: "get **milk**").rtf(
            from: NSRange(location: 0, length: 12), documentAttributes: [:])!
        pb.setData(rtf, forType: .rtf)
        pb.setString("get **milk**", forType: .string)
        #expect(StickyTextView.dropAction(for: pb) == .passthrough)
    }
}

@Suite("Markdown drop behavior")
@MainActor
struct MarkdownDropTests {

    @Test("dropping markdown files fires the import callback and consumes the drop")
    func fileDropFiresCallback() {
        let tv = editor()
        var received: [URL] = []
        tv.onDropMarkdownFiles = { received = $0 }

        let pb = scratchPasteboard()
        let url = URL(fileURLWithPath: "/tmp/groceries.md")
        pb.clearContents()
        pb.writeObjects([url as NSURL])

        #expect(tv.performDragOperation(DragStub(pasteboard: pb)))
        #expect(received == [url])
        #expect(tv.string.isEmpty)  // nothing inserted into the note itself
    }

    @Test("dropping markdown text inserts styled runs, not marker literals")
    func textDropInsertsStyled() {
        let tv = editor()
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("Title\nget **milk**\n- bread", forType: .string)

        #expect(tv.performDragOperation(DragStub(pasteboard: pb)))
        #expect(tv.string == "Title\nget milk\n\u{2022}\tbread")

        let milk = (tv.string as NSString).range(of: "milk").location
        let font = tv.textStorage!.attribute(.font, at: milk,
                                             effectiveRange: nil) as! NSFont
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }
}
