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

@Suite("Markdown typing — list triggers")
@MainActor
struct ListConversionTests {

    @Test("- space becomes a bullet")
    func bullet() {
        let tv = makeNote()
        type("Title\n- milk", into: tv)
        #expect(tv.string == "Title\n\u{2022}\tmilk")
    }

    @Test("1. space becomes a numbered item keeping the number")
    func numbered() {
        let tv = makeNote()
        type("Title\n3. eggs", into: tv)
        #expect(tv.string == "Title\n3.\teggs")
    }

    @Test("[ ] space becomes an unchecked checkbox")
    func checkbox() {
        let tv = makeNote()
        type("Title\n[ ] buy", into: tv)
        #expect(tv.string == "Title\n\u{2610}\tbuy")
    }

    @Test("the full - [ ] sequence lands as a checkbox via bullet upgrade")
    func checkboxViaBullet() {
        let tv = makeNote()
        type("Title\n- [ ] buy", into: tv)
        #expect(tv.string == "Title\n\u{2610}\tbuy")
    }

    @Test("- [x] yields a checked checkbox")
    func checkedViaBullet() {
        let tv = makeNote()
        type("Title\n- [x] done", into: tv)
        #expect(tv.string == "Title\n\u{2611}\tdone")
    }

    @Test("trigger only fires at the start of a plain paragraph")
    func midLineNoTrigger() {
        let tv = makeNote()
        type("Title\nmilk - eggs", into: tv)
        #expect(tv.string == "Title\nmilk - eggs")
    }

    @Test("list paragraphs get the hanging indent")
    func indent() {
        let tv = makeNote()
        type("Title\n- milk", into: tv)
        let style = tv.textStorage!.attribute(
            .paragraphStyle, at: 6, effectiveRange: nil) as! NSParagraphStyle
        #expect(style.headIndent == 22)
    }
}

@Suite("Markdown typing — return-key continuation")
@MainActor
struct ContinuationTests {

    @Test("bullets continue on return")
    func bullet() {
        let tv = makeNote()
        type("Title\n- milk\neggs", into: tv)
        #expect(tv.string == "Title\n\u{2022}\tmilk\n\u{2022}\teggs")
    }

    @Test("numbered lists increment on return")
    func numbered() {
        let tv = makeNote()
        type("Title\n1. milk\neggs", into: tv)
        #expect(tv.string == "Title\n1.\tmilk\n2.\teggs")
    }

    @Test("checkbox lines continue with a fresh unchecked box")
    func checkbox() {
        let tv = makeNote()
        type("Title\n[ ] milk\neggs", into: tv)
        #expect(tv.string == "Title\n\u{2610}\tmilk\n\u{2610}\teggs")
    }

    @Test("return on an empty item exits the list")
    func exitOnEmpty() {
        let tv = makeNote()
        type("Title\n1. milk\n\n", into: tv)
        // First return continues with "2.\t"; second return (empty item)
        // removes the marker and swallows the newline.
        #expect(tv.string == "Title\n1.\tmilk\n")
        let style = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect((style?.headIndent ?? 0) == 0)  // indent cleared
    }
}
