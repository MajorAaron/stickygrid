import AppKit
import Testing
@testable import StickyGridApp

@MainActor
private func makeNote(bodySize: CGFloat = 14, text: String = "") -> StickyTextView {
    let tv = StickyTextView(usingTextLayoutManager: false)
    tv.isRichText = true
    let font = NSFont(name: "Helvetica Neue", size: bodySize)!
    tv.typingAttributes = [.font: font]
    tv.bodyFont = font
    if !text.isEmpty {
        tv.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        tv.restyleHeader()
    }
    return tv
}

@MainActor
private func font(in tv: StickyTextView, at location: Int) -> NSFont {
    tv.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont
}

private func isBold(_ font: NSFont) -> Bool {
    NSFontManager.shared.traits(of: font).contains(.boldFontMask)
}

@Suite("Auto first-line header")
@MainActor
struct HeaderStylingTests {

    @Test("first paragraph is bold at 1.3x body size, body is unchanged")
    func headerAndBody() {
        let tv = makeNote(text: "Title\nbody text")
        let header = font(in: tv, at: 0)
        #expect(header.pointSize == 18) // round(14 * 1.3)
        #expect(isBold(header))
        let body = font(in: tv, at: 7)
        #expect(body.pointSize == 14)
        #expect(!isBold(body))
    }

    @Test("empty note starts typing in header style")
    func emptyNote() {
        let tv = makeNote()
        let typing = tv.typingAttributes[.font] as! NSFont
        #expect(typing.pointSize == 18)
        #expect(isBold(typing))
    }

    @Test("programmatic insertText restyles via didChangeText")
    func typingTriggersRestyle() {
        let tv = makeNote()
        tv.insertText("Hello", replacementRange: NSRange(location: 0, length: 0))
        let header = font(in: tv, at: 0)
        #expect(header.pointSize == 18)
        #expect(isBold(header))
    }

    @Test("oversized run below the first line is demoted, traits preserved")
    func demotion() {
        let tv = makeNote(text: "Title\npushed")
        let big = NSFontManager.shared.convert(
            NSFont(name: "Helvetica Neue", size: 18)!, toHaveTrait: .boldFontMask)
        tv.textStorage!.addAttribute(.font, value: big,
                                     range: NSRange(location: 6, length: 6))
        tv.restyleHeader()
        let demoted = font(in: tv, at: 6)
        #expect(demoted.pointSize == 14)
        #expect(isBold(demoted)) // bold/italic traits survive demotion
    }

    @Test("italic in the header is preserved")
    func italicHeader() {
        let tv = makeNote(text: "Title\nbody")
        let italic = NSFontManager.shared.convert(
            NSFont(name: "Helvetica Neue", size: 14)!, toHaveTrait: .italicFontMask)
        tv.textStorage!.addAttribute(.font, value: italic,
                                     range: NSRange(location: 0, length: 5))
        tv.restyleHeader()
        let header = font(in: tv, at: 0)
        #expect(header.pointSize == 18)
        #expect(isBold(header))
        #expect(NSFontManager.shared.traits(of: header).contains(.italicFontMask))
    }

    @Test("deleting the first line promotes the next line")
    func promotion() {
        let tv = makeNote(text: "Title\nsecond")
        tv.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 6), with: "")
        tv.restyleHeader()
        let promoted = font(in: tv, at: 0)
        #expect(promoted.pointSize == 18)
        #expect(isBold(promoted))
    }

    @Test("changing bodyFont rescales the header")
    func rescale() {
        let tv = makeNote(text: "Title\nbody")
        tv.bodyFont = NSFont(name: "Helvetica Neue", size: 20)!
        #expect(font(in: tv, at: 0).pointSize == 26) // round(20 * 1.3)
    }
}
