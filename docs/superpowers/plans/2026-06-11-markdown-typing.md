# Markdown Typing Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Typing markdown converts to rich formatting instantly — `**bold**`, `*italic*`, `~~strike~~`, `` `code` `` on the closing delimiter; `- `, `1. `, `[ ] ` into bullet / numbered / checkbox lists on the space — with markers vanishing and one ⌘Z restoring the literal text.

**Architecture:** A pure pattern scanner (`MarkdownTyping`) in `StickyGridCore` returns match ranges; a thin glue layer on `StickyTextView` (an `insertText` override plus an extension file) applies conversions through the existing `shouldChangeText` → `replaceCharacters` → `didChangeText` path so undo, autosave, and the first-line header restyle fire normally. List markers stay literal text + indent, exactly like today's bullets.

**Tech Stack:** Swift 6.2 SPM package, AppKit/TextKit 1, swift-testing (`@Suite`/`@Test`/`#expect`). Run tests with `swift test`.

**Spec:** `docs/superpowers/specs/2026-06-11-markdown-typing-design.md`

**Design refinement vs. spec:** `- ` becomes a bullet the moment its space is typed, so the literal keystrokes `- [ ] ` arrive as `[ ] ` typed at the start of a fresh bullet. The checkbox trigger therefore has two forms: `[ ] `/`[x] ` (also `[] `) at the start of a plain line, and the same text typed right after a bullet marker (upgrades the bullet). The spec's promised `- [ ] ` keystroke sequence works end-to-end.

**Conventions used below:**

- All scanner ranges are UTF-16 (`NSRange`-compatible) offsets relative to the paragraph string.
- Commit messages follow the repo style (`Subject: detail`), not conventional-commits.
- Repo root is the working directory for all commands.

---

### Task 1: Core inline scanner (`MarkdownTyping.inlineMatch`)

**Files:**
- Create: `Sources/StickyGridCore/MarkdownTyping.swift`
- Test: `Tests/StickyGridCoreTests/MarkdownTypingTests.swift`

- [x] **Step 1: Write the failing tests**

Create `Tests/StickyGridCoreTests/MarkdownTypingTests.swift`:

```swift
import Foundation
import Testing
@testable import StickyGridCore

@Suite("Markdown typing — inline scanner")
struct InlineMatchTests {

    /// Caret at end of string, as if the last character was just typed.
    private func match(_ s: String) -> MarkdownTyping.InlineMatch? {
        MarkdownTyping.inlineMatch(paragraph: s, caret: (s as NSString).length)
    }

    @Test("**bold** matches bold with marker-free content range")
    func bold() throws {
        let m = try #require(match("**bold**"))
        #expect(m.style == .bold)
        #expect(m.fullRange == NSRange(location: 0, length: 8))
        #expect(m.contentRange == NSRange(location: 2, length: 4))
    }

    @Test("*italic* matches italic")
    func italic() throws {
        let m = try #require(match("*italic*"))
        #expect(m.style == .italic)
        #expect(m.fullRange == NSRange(location: 0, length: 8))
        #expect(m.contentRange == NSRange(location: 1, length: 6))
    }

    @Test("~~strike~~ matches strikethrough")
    func strike() throws {
        let m = try #require(match("~~strike~~"))
        #expect(m.style == .strikethrough)
        #expect(m.contentRange == NSRange(location: 2, length: 6))
    }

    @Test("`code` matches code")
    func code() throws {
        let m = try #require(match("`code`"))
        #expect(m.style == .code)
        #expect(m.contentRange == NSRange(location: 1, length: 4))
    }

    @Test("pattern mid-paragraph: ranges are offset, prior text untouched")
    func midParagraph() throws {
        let m = try #require(match("see **this**"))
        #expect(m.style == .bold)
        #expect(m.fullRange == NSRange(location: 4, length: 8))
        #expect(m.contentRange == NSRange(location: 6, length: 4))
    }

    @Test("only text before the caret is scanned")
    func caretBound() {
        // Caret sits right after "**bold**"; trailing text is ignored.
        let s = "**bold** and more"
        let m = MarkdownTyping.inlineMatch(paragraph: s, caret: 8)
        #expect(m?.style == .bold)
        // Caret one character earlier: closer incomplete, no match.
        #expect(MarkdownTyping.inlineMatch(paragraph: s, caret: 7) == nil)
    }

    @Test("longest delimiter wins: ** is bold, not italic around a star")
    func longestWins() throws {
        #expect(try #require(match("**bold**")).style == .bold)
    }

    @Test("space directly inside the markers blocks conversion")
    func innerSpace() {
        #expect(match("** bold**") == nil)
        #expect(match("**bold **") == nil)
        #expect(match("* italic*") == nil)
    }

    @Test("empty content blocks conversion")
    func emptyContent() {
        #expect(match("****") == nil)
        #expect(match("``") == nil)
    }

    @Test("opener glued to a word or digit blocks conversion")
    func wordBoundary() {
        #expect(match("snake*case*") == nil)
        #expect(match("5*6*") == nil)
    }

    @Test("opener after punctuation or whitespace converts")
    func punctuationBoundary() {
        #expect(match("(*hi*")?.style == .italic)
        #expect(match("a *b*")?.style == .italic)
    }

    @Test("typing the second star of a closing ** never italicizes")
    func halfTypedBold() {
        // "**bold*" — one star short of closing; the single-star closer must
        // not pair with the tail of the opening "**".
        #expect(match("**bold*") == nil)
    }

    @Test("bold content may contain a single star")
    func boldWithInnerStar() throws {
        let m = try #require(match("**a*b**"))
        #expect(m.style == .bold)
        #expect(m.contentRange == NSRange(location: 2, length: 3))
    }

    @Test("no delimiter at the caret: no match")
    func noDelimiter() {
        #expect(match("plain text") == nil)
        #expect(match("*italic") == nil)
    }
}
```

- [x] **Step 2: Run the tests to verify they fail to compile (type doesn't exist)**

Run: `swift test --filter InlineMatchTests`
Expected: build error — `MarkdownTyping` not found.

- [x] **Step 3: Implement the scanner**

Create `Sources/StickyGridCore/MarkdownTyping.swift`:

```swift
import Foundation

/// Live markdown typing shortcuts: pure pattern detection consumed by
/// StickyTextView's conversion-on-type glue. All ranges are UTF-16 offsets
/// relative to the paragraph string, ready for NSTextStorage math.
/// See docs/superpowers/specs/2026-06-11-markdown-typing-design.md.
public enum MarkdownTyping {

    // MARK: Inline styles

    public enum InlineStyle: Equatable, Sendable {
        case bold, italic, strikethrough, code
    }

    public struct InlineMatch: Equatable, Sendable {
        /// The whole pattern including markers.
        public let fullRange: NSRange
        /// The content between the markers.
        public let contentRange: NSRange
        public let style: InlineStyle

        public init(fullRange: NSRange, contentRange: NSRange, style: InlineStyle) {
            self.fullRange = fullRange
            self.contentRange = contentRange
            self.style = style
        }
    }

    /// Longest first so `**` wins over `*`.
    private static let inlineMarkers: [(marker: String, style: InlineStyle)] = [
        ("**", .bold), ("~~", .strikethrough), ("*", .italic), ("`", .code),
    ]

    /// Returns the inline pattern whose closing delimiter ends exactly at
    /// `caret`, or nil. Call after a delimiter character is typed; only text
    /// before the caret is considered.
    public static func inlineMatch(paragraph: String, caret: Int) -> InlineMatch? {
        let text = paragraph as NSString
        guard caret <= text.length else { return nil }
        for (marker, style) in inlineMarkers {
            let len = (marker as NSString).length
            guard caret >= 2 * len + 1 else { continue }  // marker + content + marker
            let closerStart = caret - len
            guard text.substring(with: NSRange(location: closerStart, length: len)) == marker
            else { continue }
            // Nearest opener first; walk outward until one validates.
            var search = NSRange(location: 0, length: closerStart)
            while true {
                let opener = text.range(of: marker, options: .backwards, range: search)
                guard opener.location != NSNotFound else { break }
                if let match = validated(text: text, opener: opener, closerStart: closerStart,
                                         marker: marker, style: style, caret: caret) {
                    return match
                }
                search.length = opener.location
            }
        }
        return nil
    }

    private static func validated(
        text: NSString, opener: NSRange, closerStart: Int,
        marker: String, style: InlineStyle, caret: Int
    ) -> InlineMatch? {
        let content = NSRange(location: NSMaxRange(opener),
                              length: closerStart - NSMaxRange(opener))
        guard content.length > 0 else { return nil }
        let body = text.substring(with: content)
        // No whitespace directly inside the markers, and no marker inside the
        // content — the latter rejects the "*bold*"-shaped tail of a
        // half-typed "**bold**".
        let whitespace = CharacterSet.whitespaces
        guard let first = body.unicodeScalars.first, !whitespace.contains(first),
              let last = body.unicodeScalars.last, !whitespace.contains(last),
              !body.contains(marker)
        else { return nil }
        // The opener must sit at a word boundary: paragraph start, whitespace,
        // or punctuation — never a letter/digit, and never the marker's own
        // character (that's the tail of a longer, still-open delimiter).
        if opener.location > 0 {
            let prev = text.character(at: opener.location - 1)
            if prev == marker.utf16.first { return nil }
            if let scalar = Unicode.Scalar(prev),
               CharacterSet.alphanumerics.contains(scalar) { return nil }
        }
        return InlineMatch(
            fullRange: NSRange(location: opener.location, length: caret - opener.location),
            contentRange: content,
            style: style)
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter InlineMatchTests`
Expected: all tests PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/StickyGridCore/MarkdownTyping.swift Tests/StickyGridCoreTests/MarkdownTypingTests.swift
git commit -m "Markdown typing: pure inline pattern scanner in Core"
```

---

### Task 2: Core list triggers and line markers

**Files:**
- Modify: `Sources/StickyGridCore/MarkdownTyping.swift` (append to the enum)
- Test: `Tests/StickyGridCoreTests/MarkdownTypingTests.swift` (append suites)

- [x] **Step 1: Write the failing tests**

Append to `Tests/StickyGridCoreTests/MarkdownTypingTests.swift`:

```swift
@Suite("Markdown typing — list triggers")
struct ListTriggerTests {

    @Test("- and * with a space trigger a bullet")
    func bullet() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "- ") == .bullet)
        #expect(MarkdownTyping.listTrigger(linePrefix: "* ") == .bullet)
    }

    @Test("N. with a space triggers a numbered item keeping the typed number")
    func numbered() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "1. ") == .numbered(1))
        #expect(MarkdownTyping.listTrigger(linePrefix: "12. ") == .numbered(12))
    }

    @Test("[ ] and [x] forms trigger checkboxes")
    func checkbox() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "[ ] ") == .checkbox(checked: false))
        #expect(MarkdownTyping.listTrigger(linePrefix: "[] ") == .checkbox(checked: false))
        #expect(MarkdownTyping.listTrigger(linePrefix: "[x] ") == .checkbox(checked: true))
        #expect(MarkdownTyping.listTrigger(linePrefix: "[X] ") == .checkbox(checked: true))
    }

    @Test("anything else does not trigger")
    func noTrigger() {
        #expect(MarkdownTyping.listTrigger(linePrefix: "-") == nil)       // no space yet
        #expect(MarkdownTyping.listTrigger(linePrefix: "-  ") == nil)     // extra space
        #expect(MarkdownTyping.listTrigger(linePrefix: "a. ") == nil)     // not a number
        #expect(MarkdownTyping.listTrigger(linePrefix: "1.") == nil)      // no space yet
        #expect(MarkdownTyping.listTrigger(linePrefix: "x - ") == nil)    // mid-line
    }

    @Test("typing [ ] on a fresh bullet upgrades it to a checkbox")
    func upgrade() {
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "[ ] ") == .checkbox(checked: false))
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "[] ") == .checkbox(checked: false))
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "[x] ") == .checkbox(checked: true))
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "[ ]") == nil)
        #expect(MarkdownTyping.checkboxUpgrade(afterBullet: "milk ") == nil)
    }
}

@Suite("Markdown typing — line markers")
struct LineMarkerTests {

    @Test("literals for each marker kind")
    func literals() {
        #expect(MarkdownTyping.LineMarker.bullet.literal == "\u{2022}\t")
        #expect(MarkdownTyping.LineMarker.numbered(7).literal == "7.\t")
        #expect(MarkdownTyping.LineMarker.checkbox(checked: false).literal == "\u{2610}\t")
        #expect(MarkdownTyping.LineMarker.checkbox(checked: true).literal == "\u{2611}\t")
    }

    @Test("parse recognizes each marker at paragraph start")
    func parse() {
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "\u{2022}\tmilk") == .bullet)
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "12.\tdo it") == .numbered(12))
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "\u{2610}\ttask")
                == .checkbox(checked: false))
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "\u{2611}\tdone")
                == .checkbox(checked: true))
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "plain line") == nil)
        #expect(MarkdownTyping.LineMarker.parse(paragraph: "1月\tx") == nil)
    }

    @Test("continuation: bullet repeats, numbers increment, checkboxes reset")
    func continuation() {
        #expect(MarkdownTyping.LineMarker.bullet.continuationLiteral == "\u{2022}\t")
        #expect(MarkdownTyping.LineMarker.numbered(7).continuationLiteral == "8.\t")
        #expect(MarkdownTyping.LineMarker.checkbox(checked: true).continuationLiteral
                == "\u{2610}\t")
    }
}
```

- [x] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter "ListTriggerTests|LineMarkerTests"`
Expected: build error — `listTrigger`, `checkboxUpgrade`, `LineMarker` not found.

- [x] **Step 3: Implement triggers and markers**

Append inside `public enum MarkdownTyping { ... }` in `Sources/StickyGridCore/MarkdownTyping.swift`:

```swift
    // MARK: Line markers
    // Literal marker text + indent is the app's list representation (it
    // round-trips RTF deterministically — see the bullet design note in
    // StickyTextView). One type covers list conversion, return-key
    // continuation, and checkbox toggling.

    public enum LineMarker: Equatable, Sendable {
        case bullet
        case numbered(Int)
        case checkbox(checked: Bool)

        /// The literal marker text at the start of the paragraph.
        public var literal: String {
            switch self {
            case .bullet: return "\u{2022}\t"                       // •
            case .numbered(let n): return "\(n).\t"
            case .checkbox(let checked): return checked ? "\u{2611}\t" : "\u{2610}\t"  // ☑ / ☐
            }
        }

        /// The marker the return key starts the next line with.
        public var continuationLiteral: String {
            switch self {
            case .bullet: return LineMarker.bullet.literal
            case .numbered(let n): return LineMarker.numbered(n + 1).literal
            case .checkbox: return LineMarker.checkbox(checked: false).literal
            }
        }

        /// Parses the marker at the start of a paragraph, if any.
        public static func parse(paragraph: String) -> LineMarker? {
            if paragraph.hasPrefix(LineMarker.bullet.literal) { return .bullet }
            if paragraph.hasPrefix("\u{2610}\t") { return .checkbox(checked: false) }
            if paragraph.hasPrefix("\u{2611}\t") { return .checkbox(checked: true) }
            let digits = paragraph.prefix(while: { ("0"..."9").contains($0) })
            guard !digits.isEmpty,
                  paragraph.dropFirst(digits.count).hasPrefix(".\t"),
                  let n = Int(digits)
            else { return nil }
            return .numbered(n)
        }
    }

    // MARK: List triggers

    /// `linePrefix` is the paragraph text from its start through the caret,
    /// including the just-typed space. A trigger fires only when the marker
    /// syntax is the entire prefix — i.e. typed at the paragraph start.
    public static func listTrigger(linePrefix: String) -> LineMarker? {
        switch linePrefix {
        case "- ", "* ": return .bullet
        case "[ ] ", "[] ": return .checkbox(checked: false)
        case "[x] ", "[X] ": return .checkbox(checked: true)
        default:
            guard linePrefix.hasSuffix(". ") else { return nil }
            let digits = linePrefix.dropLast(2)
            guard !digits.isEmpty,
                  digits.allSatisfy({ ("0"..."9").contains($0) }),
                  let n = Int(digits)
            else { return nil }
            return .numbered(n)
        }
    }

    /// `- ` becomes a bullet the moment its space lands, so the canonical
    /// markdown checkbox `- [ ] ` arrives as `[ ] ` typed on a fresh bullet.
    /// `textAfterBulletMarker` is the text between the bullet marker and the
    /// caret; an exact checkbox syntax upgrades the bullet.
    public static func checkboxUpgrade(afterBullet textAfterBulletMarker: String) -> LineMarker? {
        switch textAfterBulletMarker {
        case "[ ] ", "[] ": return .checkbox(checked: false)
        case "[x] ", "[X] ": return .checkbox(checked: true)
        default: return nil
        }
    }
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "ListTriggerTests|LineMarkerTests"`
Expected: all tests PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/StickyGridCore/MarkdownTyping.swift Tests/StickyGridCoreTests/MarkdownTypingTests.swift
git commit -m "Markdown typing: list triggers and line-marker model in Core"
```

---

### Task 3: Inline conversion glue in the text view

**Files:**
- Create: `Sources/StickyGridApp/StickyTextView+Markdown.swift`
- Modify: `Sources/StickyGridApp/StickyTextView.swift` (add one override)
- Test: `Tests/StickyGridAppTests/MarkdownConversionTests.swift`

Background for the implementer: `StickyTextView` (TextKit 1 `NSTextView` subclass) already routes every formatting change through `shouldChangeText` → `textStorage.replaceCharacters`/`addAttribute` → `didChangeText`; `didChangeText` re-asserts the first-line header style (`restyleHeader`). The app target builds with `defaultIsolation(MainActor.self)`, so no explicit `@MainActor` annotations are needed in app sources; tests need `@MainActor` (see the existing `HeaderStylingTests.swift` for the pattern these tests copy).

Contingency: `NSTextView.insertText` normally works headless, but if the Task 3 tests show no text being inserted at all, host the view in an offscreen window inside `makeNote` (`NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: true).contentView = tv`) and re-run before changing any production code.

- [x] **Step 1: Write the failing tests**

Create `Tests/StickyGridAppTests/MarkdownConversionTests.swift`:

```swift
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
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter InlineConversionTests`
Expected: build error — `convertMarkdownIfNeeded` doesn't exist yet, or (once the file exists) FAIL on string equality because nothing converts.

Note: a plain build error at this step is the expected red state; proceed.

- [x] **Step 3: Add the insertText hook to StickyTextView.swift**

In `Sources/StickyGridApp/StickyTextView.swift`, directly above the `// MARK: Bullet continuation on return` section, add:

```swift
    // MARK: Markdown typing shortcuts (conversion logic in +Markdown.swift)

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        let typed = (insertString as? String)
            ?? (insertString as? NSAttributedString)?.string ?? ""
        // Single keystrokes only: pasted text and programmatic inserts (list
        // continuation markers) must not trigger conversion.
        guard typed.count == 1 else { return }
        convertMarkdownIfNeeded(afterTyping: typed)
    }
```

- [x] **Step 4: Create the conversion extension**

Create `Sources/StickyGridApp/StickyTextView+Markdown.swift`:

```swift
import AppKit
import StickyGridCore

/// Live markdown conversion: typing `**bold**`, `*italic*`, `~~strike~~`, or
/// `` `code` `` converts in place the moment the closing delimiter lands.
/// Markers vanish; breakUndoCoalescing means one ⌘Z restores them. Every
/// change goes through shouldChangeText/didChangeText so undo, autosave, and
/// the header restyle fire normally.
extension StickyTextView {

    static let codeFontName = "Menlo"

    func convertMarkdownIfNeeded(afterTyping typed: String) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let caret = selectedRange().location
        guard caret <= text.length else { return }
        let paragraph = text.paragraphRange(for: NSRange(location: caret, length: 0))
        let paragraphText = text.substring(with: paragraph)
        let caretInParagraph = caret - paragraph.location

        switch typed {
        case "*", "~", "`":
            guard let match = MarkdownTyping.inlineMatch(
                paragraph: paragraphText, caret: caretInParagraph) else { return }
            applyInline(match, paragraphStart: paragraph.location)
        default:
            return
        }
    }

    private func applyInline(_ match: MarkdownTyping.InlineMatch, paragraphStart: Int) {
        guard let storage = textStorage else { return }
        let full = NSRange(location: paragraphStart + match.fullRange.location,
                           length: match.fullRange.length)
        let content = NSRange(location: paragraphStart + match.contentRange.location,
                              length: match.contentRange.length)

        // Patterns typed inside an existing code span stay literal.
        if let font = storage.attribute(.font, at: full.location,
                                        effectiveRange: nil) as? NSFont,
           font.fontName.hasPrefix(Self.codeFontName) { return }

        let styled = NSMutableAttributedString(
            attributedString: storage.attributedSubstring(from: content))
        let styledRange = NSRange(location: 0, length: styled.length)
        let fontManager = NSFontManager.shared
        switch match.style {
        case .bold, .italic:
            let trait: NSFontTraitMask = match.style == .bold ? .boldFontMask : .italicFontMask
            styled.enumerateAttribute(.font, in: styledRange) { value, subrange, _ in
                let font = (value as? NSFont) ?? bodyFont
                styled.addAttribute(.font, value: fontManager.convert(font, toHaveTrait: trait),
                                    range: subrange)
            }
        case .strikethrough:
            styled.addAttribute(.strikethroughStyle,
                                value: NSUnderlineStyle.single.rawValue, range: styledRange)
        case .code:
            // Per-run size so a code span on the header line stays header-sized.
            styled.enumerateAttribute(.font, in: styledRange) { value, subrange, _ in
                let size = ((value as? NSFont) ?? bodyFont).pointSize
                let mono = NSFont(name: Self.codeFontName, size: size)
                    ?? .monospacedSystemFont(ofSize: size, weight: .regular)
                styled.addAttribute(.font, value: mono, range: subrange)
            }
        }

        guard shouldChangeText(in: full, replacementString: styled.string) else { return }
        // The just-typed delimiter carried plain typing attributes; saving and
        // restoring them keeps typing unstyled after the converted run.
        let savedTyping = typingAttributes
        breakUndoCoalescing()
        storage.beginEditing()
        storage.replaceCharacters(in: full, with: styled)
        storage.endEditing()
        didChangeText()
        setSelectedRange(NSRange(location: full.location + styled.length, length: 0))
        typingAttributes = savedTyping
    }
}
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter InlineConversionTests`
Expected: all tests PASS.

If `noConversionInCode` fails because the code-span font check sees the wrong run, verify the guard reads the font at `full.location` (the opener position inside the mono run).

- [x] **Step 6: Run the full suite (header tests must still pass)**

Run: `swift test`
Expected: all tests PASS — especially `HeaderStylingTests`, which exercise the same `didChangeText`/`restyleHeader` path the conversion now also drives.

- [x] **Step 7: Commit**

```bash
git add Sources/StickyGridApp/StickyTextView.swift Sources/StickyGridApp/StickyTextView+Markdown.swift Tests/StickyGridAppTests/MarkdownConversionTests.swift
git commit -m "Markdown typing: live inline conversion (bold, italic, strike, code)"
```

---

### Task 4: List trigger conversion and checkbox upgrade

**Files:**
- Modify: `Sources/StickyGridApp/StickyTextView+Markdown.swift`
- Modify: `Sources/StickyGridApp/StickyTextView.swift` (import Core, share the bullet literal, open up `applyListIndent`)
- Test: `Tests/StickyGridAppTests/MarkdownConversionTests.swift` (append a suite)

- [x] **Step 1: Write the failing tests**

Append to `Tests/StickyGridAppTests/MarkdownConversionTests.swift`:

```swift
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
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ListConversionTests`
Expected: FAIL — strings keep their literal `- ` / `[ ] ` prefixes (no conversion happens yet).

- [x] **Step 3: Prepare StickyTextView.swift**

Three small edits in `Sources/StickyGridApp/StickyTextView.swift`:

1. Add the import at the top (below `import AppKit`):

```swift
import StickyGridCore
```

2. Make the Core line-marker model the single source of truth for the bullet literal — replace:

```swift
    static let bulletPrefix = "•\t"
```

with:

```swift
    static let bulletPrefix = MarkdownTyping.LineMarker.bullet.literal
```

3. Let the extension file reach the indent helper — change the access level of `applyListIndent` from:

```swift
    private func applyListIndent(_ on: Bool, to range: NSRange, storage: NSTextStorage) {
```

to:

```swift
    func applyListIndent(_ on: Bool, to range: NSRange, storage: NSTextStorage) {
```

- [x] **Step 4: Add list conversion to the extension**

In `Sources/StickyGridApp/StickyTextView+Markdown.swift`, replace the `default: return` arm of the `switch typed` in `convertMarkdownIfNeeded` with:

```swift
        case " ":
            let prefix = (paragraphText as NSString).substring(to: caretInParagraph)
            if MarkdownTyping.LineMarker.parse(paragraph: paragraphText) == nil,
               let marker = MarkdownTyping.listTrigger(linePrefix: prefix) {
                applyListMarker(marker, replacing: NSRange(location: paragraph.location,
                                                           length: caretInParagraph))
            } else if prefix.hasPrefix(Self.bulletPrefix),
                      let marker = MarkdownTyping.checkboxUpgrade(
                          afterBullet: String(prefix.dropFirst(Self.bulletPrefix.count))) {
                applyListMarker(marker, replacing: NSRange(location: paragraph.location,
                                                           length: caretInParagraph))
            }
        default:
            return
```

And add the apply method below `applyInline`:

```swift
    private func applyListMarker(_ marker: MarkdownTyping.LineMarker,
                                 replacing typedRange: NSRange) {
        guard let storage = textStorage else { return }
        let literal = marker.literal
        guard shouldChangeText(in: typedRange, replacementString: literal) else { return }
        breakUndoCoalescing()
        storage.beginEditing()
        storage.replaceCharacters(
            in: typedRange,
            with: NSAttributedString(string: literal, attributes: typingAttributes))
        storage.endEditing()
        let paragraph = (storage.string as NSString)
            .paragraphRange(for: NSRange(location: typedRange.location, length: 0))
        applyListIndent(true, to: paragraph, storage: storage)
        didChangeText()
        setSelectedRange(NSRange(location: typedRange.location + (literal as NSString).length,
                                 length: 0))
    }
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ListConversionTests`
Expected: all tests PASS.

- [x] **Step 6: Run the full suite**

Run: `swift test`
Expected: all tests PASS (bullet toggle and header tests unaffected — `bulletPrefix` kept its `"•\t"` value, now sourced from Core).

- [x] **Step 7: Commit**

```bash
git add Sources/StickyGridApp/StickyTextView.swift Sources/StickyGridApp/StickyTextView+Markdown.swift Tests/StickyGridAppTests/MarkdownConversionTests.swift
git commit -m "Markdown typing: list triggers — bullets, numbered, checkboxes"
```

---

### Task 5: Return-key continuation for all marker kinds

**Files:**
- Modify: `Sources/StickyGridApp/StickyTextView.swift` (rewrite `insertNewline`)
- Test: `Tests/StickyGridAppTests/MarkdownConversionTests.swift` (append a suite)

Today `insertNewline` only continues `•\t` bullets. `MarkdownTyping.LineMarker` generalizes it: bullets repeat, numbers increment, checkboxes continue unchecked, and return on an empty item exits the list.

- [x] **Step 1: Write the failing tests**

Append to `Tests/StickyGridAppTests/MarkdownConversionTests.swift`:

```swift
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
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ContinuationTests`
Expected: `bullet` PASSES (existing behavior); `numbered`, `checkbox`, `exitOnEmpty` FAIL (no continuation for those markers — `numbered` ends with plain `eggs`).

- [x] **Step 3: Rewrite insertNewline**

In `Sources/StickyGridApp/StickyTextView.swift`, replace the entire `// MARK: Bullet continuation on return` section (the `insertNewline` override) with:

```swift
    // MARK: List continuation on return
    // Bullets repeat, numbered items increment, checkboxes continue
    // unchecked. Continuation markers are inserted via insertText but are
    // multi-character, so the markdown conversion hook ignores them.

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else { return super.insertNewline(sender) }
        let text = storage.string as NSString
        let caret = selectedRange()
        guard caret.length == 0, text.length > 0 else { return super.insertNewline(sender) }

        let paragraph = text.paragraphRange(for: caret)
        guard let marker = MarkdownTyping.LineMarker.parse(
            paragraph: text.substring(with: paragraph)) else {
            return super.insertNewline(sender)
        }

        // Empty item + return = leave the list (like every notes app).
        let body = text.substring(with: paragraph)
            .dropFirst(marker.literal.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            let markerRange = NSRange(location: paragraph.location,
                                      length: (marker.literal as NSString).length)
            if shouldChangeText(in: markerRange, replacementString: "") {
                storage.replaceCharacters(in: markerRange, with: "")
                didChangeText()
            }
            applyListIndent(false,
                            to: NSRange(location: markerRange.location, length: 0),
                            storage: storage)
            return
        }

        super.insertNewline(sender)
        insertText(marker.continuationLiteral, replacementRange: selectedRange())
    }
```

This replaces the old bullet-only logic; the `paragraphHasMarker`/`paragraphIsBulleted` helpers remain in use by `toggleBulletList` and must stay.

- [x] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ContinuationTests`
Expected: all tests PASS.

- [x] **Step 5: Run the full suite**

Run: `swift test`
Expected: all tests PASS.

- [x] **Step 6: Commit**

```bash
git add Sources/StickyGridApp/StickyTextView.swift Tests/StickyGridAppTests/MarkdownConversionTests.swift
git commit -m "Markdown typing: return continues numbered lists and checkboxes"
```

---

### Task 6: Clickable checkboxes

**Files:**
- Modify: `Sources/StickyGridApp/StickyTextView+Markdown.swift` (toggle + hit test)
- Modify: `Sources/StickyGridApp/StickyTextView.swift` (mouseDown override)
- Test: `Tests/StickyGridAppTests/MarkdownConversionTests.swift` (append a suite)

The toggle is split from the hit test so it's unit-testable: `toggleCheckbox(at:)` takes a character index; `checkboxIndex(at:)` maps a mouse event to that index (verified manually — synthesizing NSEvents headless is not worth it).

- [x] **Step 1: Write the failing tests**

Append to `Tests/StickyGridAppTests/MarkdownConversionTests.swift`:

```swift
@Suite("Markdown typing — checkbox toggle")
@MainActor
struct CheckboxToggleTests {

    @Test("toggling flips the glyph both ways")
    func toggle() {
        let tv = makeNote()
        type("Title\n[ ] buy", into: tv)
        #expect(tv.toggleCheckbox(at: 6))
        #expect(tv.string == "Title\n\u{2611}\tbuy")
        #expect(tv.toggleCheckbox(at: 6))
        #expect(tv.string == "Title\n\u{2610}\tbuy")
    }

    @Test("only the marker position toggles")
    func onlyMarker() {
        let tv = makeNote()
        type("Title\n[ ] buy", into: tv)
        #expect(!tv.toggleCheckbox(at: 8))   // body text, not the marker
        #expect(!tv.toggleCheckbox(at: 0))   // header line, no marker
        #expect(tv.string == "Title\n\u{2610}\tbuy")
    }
}
```

- [x] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter CheckboxToggleTests`
Expected: build error — `toggleCheckbox(at:)` doesn't exist.

- [x] **Step 3: Implement toggle and hit test**

Append inside the extension in `Sources/StickyGridApp/StickyTextView+Markdown.swift`:

```swift
    // MARK: Checkbox toggling

    /// Toggles the checkbox marker whose glyph starts at `index`. Returns
    /// true when a toggle happened. Undoable as a single step.
    @discardableResult
    func toggleCheckbox(at index: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let text = storage.string as NSString
        guard index < text.length else { return false }
        let paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
        guard paragraph.location == index,
              let marker = MarkdownTyping.LineMarker.parse(
                  paragraph: text.substring(with: paragraph)),
              case .checkbox(let checked) = marker
        else { return false }

        let range = NSRange(location: index, length: 1)
        let replacement = checked ? "\u{2610}" : "\u{2611}"
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        breakUndoCoalescing()
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        return true
    }

    /// Character index of the checkbox glyph under a click, or nil. The click
    /// must land on the glyph itself, not merely on its line.
    func checkboxIndex(at event: NSEvent) -> Int? {
        guard let layoutManager, let textContainer,
              let storage = textStorage, storage.length > 0 else { return nil }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let index = layoutManager.characterIndex(
            for: point, in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length else { return nil }
        let ch = (storage.string as NSString).character(at: index)
        guard ch == 0x2610 || ch == 0x2611 else { return nil }  // ☐ / ☑
        let glyphs = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1),
            actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        guard rect.insetBy(dx: -2, dy: -2).contains(point) else { return nil }
        return index
    }
```

In `Sources/StickyGridApp/StickyTextView.swift`, directly below the `insertText` override added in Task 3, add:

```swift
    override func mouseDown(with event: NSEvent) {
        if let index = checkboxIndex(at: event), toggleCheckbox(at: index) { return }
        super.mouseDown(with: event)
    }
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CheckboxToggleTests`
Expected: all tests PASS.

- [x] **Step 5: Run the full suite**

Run: `swift test`
Expected: all tests PASS.

- [x] **Step 6: Commit**

```bash
git add Sources/StickyGridApp/StickyTextView.swift Sources/StickyGridApp/StickyTextView+Markdown.swift Tests/StickyGridAppTests/MarkdownConversionTests.swift
git commit -m "Markdown typing: clickable checkbox markers"
```

---

### Task 7: README, build, and manual verification

**Files:**
- Modify: `README.md`

- [x] **Step 1: Document the feature in the README**

In `README.md`, in the `## Features` list, directly below the "Rich text: …" bullet, add:

```markdown
- Markdown typing shortcuts: `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``
  convert as you type; `- `, `1. `, and `- [ ] ` start bullet, numbered, and
  clickable-checkbox lists. Markers vanish; ⌘Z brings them back.
```

- [x] **Step 2: Run the full test suite**

Run: `swift test`
Expected: all tests PASS.

- [x] **Step 3: Build the app bundle**

Run: `./Scripts/build-app.sh`
Expected: exits 0, `build/StickyGrid.app` assembled.

- [x] **Step 4: Manual verification in the running app**

Run: `open build/StickyGrid.app`, create a note, and verify each item:

- Type `**bold**`, `*italic*`, `~~strike~~`, `` `code` `` on a body line → each converts live, markers vanish, continuing to type is unstyled.
- ⌘Z immediately after a conversion → the literal markers come back; a second ⌘Z removes the typed text.
- Type `**hi**` as the first line → converts, header size preserved.
- Type `- `, `1. `, `- [ ] ` at line starts → bullet, numbered item, checkbox; return continues each list (numbers increment); return on an empty item exits.
- Click a checkbox glyph → toggles ☐/☑; ⌘Z untoggles; clicking body text does not toggle.
- Quit and relaunch → all converted formatting (including checkboxes and numbering) survives the RTF round-trip.
- ⇧⌘L bullet toggle and the hover-toolbar formatting buttons still behave as before.

- [x] **Step 5: Commit**

```bash
git add README.md
git commit -m "README: document markdown typing shortcuts"
```

---

## Accepted edge cases (deliberate, do not "fix" in this plan)

- No global renumbering when a middle numbered item is deleted (per spec).
- Three-digit-plus numbered markers (`100.\t`) overrun the 22 pt tab stop; the
  text after the tab shifts right. Cosmetic, rare.
- ⇧⌘L on a numbered/checkbox line prepends a bullet marker rather than
  swapping markers. Pre-existing toggle semantics; out of scope.
- Underscore emphasis (`_x_`, `__x__`) intentionally not supported.
- Paste never converts (single-keystroke guard) — paste-markdown support is a
  spec'd non-goal.
