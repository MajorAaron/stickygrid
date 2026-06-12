import AppKit
import StickyGridCore
import Testing
@testable import StickyGridApp

/// Loads RTF into a fresh editor the way openWindow does, header restyle
/// included, mirroring MarkdownFileImportTests.
@MainActor
private func editor(loading rtf: Data) -> StickyTextView {
    let font = NSFont(name: "Helvetica Neue", size: 14)!
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
private func isBold(at location: Int, in tv: StickyTextView) -> Bool {
    let font = tv.textStorage!.attribute(.font, at: location,
                                         effectiveRange: nil) as! NSFont
    return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
}

@Suite("Markdown capture rendering")
@MainActor
struct MarkdownCaptureTests {

    @Test("a markdown request renders styles instead of literal asterisks")
    func markdownRequestRenders() {
        let request = CaptureRequest(text: "note\nget **milk**", markdown: true)
        let content = WindowManager.captureContent(for: request,
                                                   record: NoteRecord(frame: .zero))
        let tv = editor(loading: content.rtf!)
        #expect(tv.string == "note\nget milk")
        let milk = (tv.string as NSString).range(of: "milk").location
        #expect(isBold(at: milk, in: tv))
        #expect(!isBold(at: milk - 4, in: tv))
    }

    @Test("the same body without the flag stays literal, as today")
    func plainRequestUntouched() {
        let request = CaptureRequest(text: "note\nget **milk**")
        let content = WindowManager.captureContent(for: request,
                                                   record: NoteRecord(frame: .zero))
        #expect(editor(loading: content.rtf!).string == "note\nget **milk**")
        #expect(content.titleSnippet == request.titleSnippet)
    }

    @Test("markdown title snippet comes from the rendered text")
    func renderedTitleSnippet() {
        let request = CaptureRequest(text: "# Big Plans\nbody", markdown: true)
        let content = WindowManager.captureContent(for: request,
                                                   record: NoteRecord(frame: .zero))
        #expect(content.titleSnippet == "Big Plans")
    }

    @Test("empty text yields no RTF for either path")
    func emptyText() {
        let record = NoteRecord(frame: .zero)
        #expect(WindowManager.captureContent(
            for: CaptureRequest(text: ""), record: record).rtf == nil)
        #expect(WindowManager.captureContent(
            for: CaptureRequest(text: "", markdown: true), record: record).rtf == nil)
    }
}
