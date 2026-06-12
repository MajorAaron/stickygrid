import AppKit
import Testing
@testable import StickyGridApp

@MainActor
private func makeNote(bodySize: CGFloat = 14) -> StickyTextView {
    let tv = StickyTextView(usingTextLayoutManager: false)
    tv.isRichText = true
    let font = NSFont(name: "Helvetica Neue", size: bodySize)!
    tv.typingAttributes = [.font: font]
    tv.bodyFont = font
    return tv
}

/// Simulates typing: one insertText per character, return key via
/// insertNewline — the same paths real keystrokes take.
@MainActor
private func type(_ text: String, into tv: StickyTextView) {
    for ch in text {
        if ch == "\n" {
            tv.insertNewline(nil)
        } else {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
        }
    }
}

@MainActor
private func font(in tv: StickyTextView, at location: Int) -> NSFont {
    tv.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont
}

private func isBold(_ font: NSFont) -> Bool {
    NSFontManager.shared.traits(of: font).contains(.boldFontMask)
}

private func isItalic(_ font: NSFont) -> Bool {
    NSFontManager.shared.traits(of: font).contains(.italicFontMask)
}

@Suite("Markdown typing — inline conversion")
@MainActor
struct InlineConversionTests {

    @Test("typing **bold** on a body line converts, removes markers")
    func bold() {
        let tv = makeNote()
        type("Title\n**bold**", into: tv)
        #expect(tv.string == "Title\nbold")
        let f = font(in: tv, at: 6)
        #expect(isBold(f))
        #expect(f.pointSize == 14)  // body size, not header size
    }

    @Test("typing continues unstyled after a conversion")
    func typingAfterConversion() {
        let tv = makeNote()
        type("Title\n**bold** x", into: tv)
        #expect(tv.string == "Title\nbold x")
        #expect(!isBold(font(in: tv, at: 10)))  // the trailing "x"
    }

    @Test("*italic* converts")
    func italic() {
        let tv = makeNote()
        type("Title\na *b*", into: tv)
        #expect(tv.string == "Title\na b")
        #expect(isItalic(font(in: tv, at: 8)))
    }

    @Test("~~strike~~ converts to strikethrough")
    func strike() {
        let tv = makeNote()
        type("Title\n~~done~~", into: tv)
        #expect(tv.string == "Title\ndone")
        let style = tv.textStorage!.attribute(
            .strikethroughStyle, at: 6, effectiveRange: nil) as? Int
        #expect(style == NSUnderlineStyle.single.rawValue)
    }

    @Test("`code` converts to the mono font at the run's size")
    func code() {
        let tv = makeNote()
        type("Title\n`xy`", into: tv)
        #expect(tv.string == "Title\nxy")
        let f = font(in: tv, at: 6)
        #expect(f.fontName.hasPrefix("Menlo"))
        #expect(f.pointSize == 14)
    }

    @Test("patterns typed inside an existing code span stay literal")
    func noConversionInCode() {
        let tv = makeNote()
        type("Title\n`ab cd`", into: tv)
        #expect(tv.string == "Title\nab cd")
        // Caret after "ab " — inside the mono run, after a space so the
        // scanner would otherwise match the italic pattern.
        tv.setSelectedRange(NSRange(location: 9, length: 0))
        type("*x*", into: tv)
        #expect(tv.string == "Title\nab *x*cd")  // guard kept it literal
    }

    @Test("conversion on the first line keeps the header style")
    func headerLine() {
        let tv = makeNote()
        type("**hi**", into: tv)
        #expect(tv.string == "hi")
        let f = font(in: tv, at: 0)
        #expect(isBold(f))
        #expect(f.pointSize == 18)  // round(14 * 1.3) — header restyle intact
    }

    @Test("invalid pattern stays literal")
    func invalid() {
        let tv = makeNote()
        type("Title\n** bold**", into: tv)
        #expect(tv.string == "Title\n** bold**")
    }
}
