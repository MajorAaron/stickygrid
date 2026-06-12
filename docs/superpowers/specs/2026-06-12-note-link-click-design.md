# Clickable Note Links — stickygrid:// URLs live inside note text

**Date:** 2026-06-12
**Status:** Approved (automated run — decisions noted in run report)

## Problem

`stickygrid://open?note=<query>` deep links shipped this morning, but inside a
note they are inert text. The whole point of an address scheme for notes is
note-to-note linking: paste a link to "Project Plan" inside "Weekly Review"
and click it. There is also no way to *get* a note's link from the GUI — only
`sticky open --print` produces one.

## Goals

- URLs typed or pasted into a note render as clickable links.
- Clicking a `stickygrid://open` link raises the target note — in-process,
  so it works even when LaunchServices hasn't registered the app
  (`swift run` dev builds).
- Clicking a web link opens the browser (default NSTextView behavior).
- File → **Copy Link to Note** (⌥⇧⌘C) copies the front note's
  `stickygrid://open?note=<full-uuid>` URL for pasting anywhere.

## Non-Goals

- Display-text links ("rich" links where `Project Plan` is the visible text).
  Textual URLs only; pretty links are a future pass.
- Preserving `.link` attributes from pasted rich text whose display text is
  not itself a URL — link styling is recomputed from the visible text.
- Linkifying other URL schemes (mailto:, file:). `stickygrid`, `http`,
  `https` only.

## Design

### Core: `LinkDetection` (new, `Sources/StickyGridCore/LinkDetection.swift`)

Pure Foundation. NSDataDetector cannot match custom schemes, so detection is
an `NSRegularExpression` over `(?:stickygrid|https?)://\S+`, case-insensitive
on the scheme, with trailing punctuation `.,;:!?` and closers `)]}>"'`
trimmed from each match (so `(see https://x.test)` links `https://x.test`).

```swift
public enum LinkDetection {
    public struct Match: Equatable {
        public var range: NSRange   // UTF-16, ready for NSAttributedString
        public var url: URL
    }
    public static func matches(in text: String) -> [Match]
}
```

Matches whose trimmed text fails `URL(string:)` are dropped. NSRegularExpression
hands back UTF-16 NSRanges natively, which is exactly what attribute
application needs — a test pins this with non-BMP characters before the URL.

### App: link restyle (`Sources/StickyGridApp/StickyTextView+Links.swift`)

`restyleLinks()` follows the `restyleHeader()` invariant pattern: called from
`didChangeText()` and after `loadRTF`, mutates attributes only, never calls
`didChangeText`, so it cannot recurse.

- Remove `.link` across the whole storage, then add `.link: url` for every
  `LinkDetection.matches` range. Recompute-from-text keeps stale links from
  surviving edits that break the URL.
- Rendering uses NSTextView's default `linkTextAttributes` (blue +
  underline) — legible on all eight note colors, universally read as
  "clickable".

### App: click routing

`RichTextEditor.Coordinator` implements
`textView(_:clickedOnLink:at:) -> Bool`:

- Link parses as `OpenRequest` → `viewModel.onOpenNoteLink(query)` → wired by
  WindowManager to `focusNote(query:)`. Returns `true` (handled in-process;
  no LaunchServices round-trip).
- Anything else returns `false` — NSTextView's default opens web links in the
  browser.

`NoteViewModel` gains `onOpenNoteLink: (String) -> Void`, wired where the
other callbacks are.

### App: Copy Link to Note

`WindowManager.copyFrontNoteLink(_:)` — key window's note id →
`OpenRequest.openURL(query: id.uuidString.lowercased())` → pasteboard as
plain string (most pasteable form). Beep when no note is key. File menu item
after "Copy as Markdown", key equivalent ⌥⇧⌘C (sibling of ⌥⌘C).

Full UUIDs link precisely and survive retitling; `bestMatch` still resolves
hand-typed title links.

## Testing

- **Core `LinkDetectionTests`:** stickygrid/http/https matches with exact
  NSRanges, UTF-16 offsets with non-BMP text, trailing-punctuation trim,
  multiple matches, scheme-less text and bare words yield nothing.
- **App `NoteLinkTests` (@MainActor, headless):**
  - `restyleLinks()` applies `.link` over the URL range only; editing the URL
    text clears the stale attribute.
  - Coordinator delegate: stickygrid URL fires `onOpenNoteLink` with the
    query and returns true; https URL returns false and fires nothing.
- Pasteboard write and menu glue are manual-verification (GUI), per the
  standing convention.

## Risks

- Re-scanning the whole text every keystroke: notes are small by design;
  restyleHeader already walks the same storage per edit.
- `.link` round-trips through RTF persistence; restyle on load recomputes it
  anyway, so stale persisted links self-heal.
