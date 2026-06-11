# Auto First-Line Note Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first paragraph of every note automatically renders as a header — bold, at ~1.3× the note's body font size — with no user action.

**Architecture:** A `restyleHeader()` invariant pass on `StickyTextView` (TextKit 1 `NSTextView` subclass), re-run after every edit via a `didChangeText()` override, after RTF load, and after per-note font changes. The header style is baked into the RTF attributes, so persistence and `titleSnippet` are untouched. No changes to `StickyGridCore`.

**Tech Stack:** Swift 6.2 package, AppKit (TextKit 1, `NSFontManager`), Swift Testing framework.

**Spec:** `docs/superpowers/specs/2026-06-11-note-header-design.md`

## File structure

- Modify `Package.swift` — add a `StickyGridAppTests` test target (the app target is testable; it's an executable target, which SPM supports in test dependencies).
- Create `Tests/StickyGridAppTests/HeaderStylingTests.swift` — unit tests for the restyle invariant.
- Modify `Sources/StickyGridApp/StickyTextView.swift` — add `bodyFont`, `restyleHeader()`, `didChangeText()` override.
- Modify `Sources/StickyGridApp/RichTextEditor.swift` — set `bodyFont` when the view is created.
- Modify `Sources/StickyGridApp/RichTextController.swift` — restyle after `loadRTF`; update `bodyFont` in `applyFont`.
- Modify `README.md` — add the feature bullet.

Key invariants (the whole feature is these two rules, asserted idempotently):
1. Every run in the first paragraph is bold at `round(bodyFont.pointSize × 1.3)`, italic preserved.
2. Any run *after* the first paragraph whose size exceeds the body size is demoted to body size, traits preserved. (Size is a safe discriminator: the app has no per-run size editing, so only header-derived text is ever oversized.)

Typing attributes follow the caret's paragraph: header style in the first paragraph; demoted to body size *with bold stripped* below it (fresh typing on a body line should look like body text — bold stripping applies only to the oversized, header-inherited case, never to user-applied bold at body size).

---

### Task 1: Failing tests for the header invariant

**Files:**
- Modify: `Package.swift:18-21`
- Create: `Tests/StickyGridAppTests/HeaderStylingTests.swift`

- [ ] **Step 1: Add the test target to Package.swift**

After the existing `StickyGridCoreTests` test target, add:

```swift
.testTarget(
    name: "StickyGridAppTests",
    dependencies: ["StickyGridApp"]
),
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/StickyGridAppTests/HeaderStylingTests.swift`. The app target defaults to `MainActor` isolation, so the suite and helpers are `@MainActor`.

```swift
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
```

- [ ] **Step 3: Run tests to verify they fail to compile**

Run: `swift test 2>&1 | tail -20`
Expected: compile errors — `StickyTextView` has no member `bodyFont` / `restyleHeader`. (A compile failure is this feature's "red" state.)

- [ ] **Step 4: Commit the red state? No — Swift can't commit non-compiling tests separately.**

Skip committing here; Task 2 makes it green and commits both together.

---

### Task 2: Implement the restyle pass in StickyTextView

**Files:**
- Modify: `Sources/StickyGridApp/StickyTextView.swift` (add a new MARK section after the bold/italic section, around line 49)
- Test: `Tests/StickyGridAppTests/HeaderStylingTests.swift` (from Task 1)

- [ ] **Step 1: Add the header section to StickyTextView**

```swift
// MARK: Auto first-line header
// The first paragraph always renders as a header: bold, headerScale × the
// note's body size. restyleHeader() re-asserts this invariant after every
// edit; it never calls didChangeText, so it cannot recurse. Demotion of
// oversized runs below the header is safe because the app has no per-run
// size editing — only header-derived text is ever oversized.

static let headerScale: CGFloat = 1.3

/// The note's body font; the header style is derived from it. Set by
/// RichTextEditor at creation and by RichTextController.applyFont.
var bodyFont: NSFont = .userFont(ofSize: 14) ?? .systemFont(ofSize: 14) {
    didSet { restyleHeader() }
}

override func didChangeText() {
    super.didChangeText()
    restyleHeader()
}

func restyleHeader() {
    guard let storage = textStorage else { return }
    let fontManager = NSFontManager.shared
    let headerSize = (bodyFont.pointSize * Self.headerScale).rounded()
    let text = storage.string as NSString

    func headerVariant(of font: NSFont) -> NSFont {
        fontManager.convert(fontManager.convert(font, toSize: headerSize),
                            toHaveTrait: .boldFontMask)
    }

    if text.length > 0 {
        let header = text.paragraphRange(for: NSRange(location: 0, length: 0))
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: header) { value, subrange, _ in
            let font = (value as? NSFont) ?? bodyFont
            storage.addAttribute(.font, value: headerVariant(of: font),
                                 range: subrange)
        }
        let rest = NSRange(location: NSMaxRange(header),
                           length: text.length - NSMaxRange(header))
        if rest.length > 0 {
            storage.enumerateAttribute(.font, in: rest) { value, subrange, _ in
                guard let font = value as? NSFont,
                      font.pointSize > bodyFont.pointSize else { return }
                storage.addAttribute(
                    .font,
                    value: fontManager.convert(font, toSize: bodyFont.pointSize),
                    range: subrange)
            }
        }
        storage.endEditing()
    }

    // Keep typing attributes in step with the caret's paragraph so newly
    // typed text never appears at the wrong size.
    let caret = min(selectedRange().location, text.length)
    let inHeader = text.length == 0
        || text.paragraphRange(for: NSRange(location: caret, length: 0)).location == 0
    let typingFont = (typingAttributes[.font] as? NSFont) ?? bodyFont
    if inHeader {
        typingAttributes[.font] = headerVariant(of: typingFont)
    } else if typingFont.pointSize > bodyFont.pointSize {
        // Inherited from the header: body size, bold off — fresh typing on
        // a body line should look like body text. User-applied bold is at
        // body size and never enters this branch.
        let demoted = fontManager.convert(typingFont, toSize: bodyFont.pointSize)
        typingAttributes[.font] = fontManager.convert(demoted,
                                                      toNotHaveTrait: .boldFontMask)
    }
}
```

Known accepted quirk (from the spec): a caret-only bold toggle inside the header flips typing attributes without an edit; the restyle re-asserts bold on the next keystroke. Effectively a no-op, by design.

- [ ] **Step 2: Run the tests**

Run: `swift test 2>&1 | tail -10`
Expected: all suites PASS (treemap, persistence, and the 7 new header tests).

- [ ] **Step 3: Commit**

```bash
git add Package.swift Tests/StickyGridAppTests Sources/StickyGridApp/StickyTextView.swift
git commit -m "Auto first-line header: restyle invariant in StickyTextView"
```

---

### Task 3: Wire the restyle into load, font changes, and view creation

**Files:**
- Modify: `Sources/StickyGridApp/RichTextEditor.swift:41` (after the `typingAttributes` line in `makeNSView`)
- Modify: `Sources/StickyGridApp/RichTextController.swift:44` (end of `applyFont`) and `:74` (end of `loadRTF`)

- [ ] **Step 1: Set bodyFont in RichTextEditor.makeNSView**

After `textView.typingAttributes = [.font: font, .foregroundColor: color]` add:

```swift
textView.bodyFont = font  // didSet restyles: empty notes start in header style
```

(Must come after the `typingAttributes` assignment — the didSet promotes the typing font to the header variant.)

- [ ] **Step 2: Restyle after RTF load in RichTextController.loadRTF**

`setAttributedString` does not call `didChangeText()` (that's a user-edit path), so after `storage.setAttributedString(attributed)` add:

```swift
tv.restyleHeader()  // upgrades pre-header notes on first load
```

- [ ] **Step 3: Update bodyFont in RichTextController.applyFont**

At the end of `applyFont`, after `tv.typingAttributes[.font] = base`, add:

```swift
tv.bodyFont = base  // didSet re-promotes the first paragraph at the new size
```

(The enumerate loop above it has just re-fonted the whole note — header included — to the new body font; the didSet restyle then re-promotes the first paragraph. Order matters: it must come after the `typingAttributes` line.)

- [ ] **Step 4: Run the full test suite and build the app**

Run: `swift test 2>&1 | tail -5 && ./Scripts/build-app.sh`
Expected: tests PASS; `Built build/StickyGrid.app`.

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyGridApp/RichTextEditor.swift Sources/StickyGridApp/RichTextController.swift
git commit -m "Wire header restyle into note load, font changes, and view creation"
```

---

### Task 4: README + manual verification

**Files:**
- Modify: `README.md:13-17` (features list)

- [ ] **Step 1: Add the feature bullet to README**

In the Features list, after the rich-text bullet, add:

```markdown
- The first line of every note is its title — automatically bold and larger,
  so a wall of notes stays scannable
```

- [ ] **Step 2: Manual verification in the running app**

Run: `open build/StickyGrid.app` and check, per the spec's test list:
1. Type a multi-line note → first line bold/large, body normal.
2. Insert a newline mid-header → pushed-down text demotes to body size.
3. Delete the first line → the next line promotes.
4. Change per-note font family and size from the toolbar → header rescales.
5. Quit and relaunch → styling survives the RTF round-trip; any pre-existing
   note upgrades on load.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "README: document auto first-line header"
```
