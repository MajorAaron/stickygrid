# Note Header Styling — Design

Date: 2026-06-11
Status: Approved (auto first-line header chosen over a heading toggle command
and a separate title field)

## Goal

Make it obvious at a glance what each note is for: the first line of every
note renders as a header — bold, larger — with no user effort.

## Behavior

- The first paragraph of a note renders in a header style: **bold**, at
  ~1.3× the note's font size, in the note's font family.
- Automatic and continuous: type a title, press return, and subsequent text
  is body-sized. Delete the first line and the next line becomes the header.
- No new commands, menu items, or toolbar buttons.
- Existing notes upgrade automatically: the styling pass runs on load, not
  just on edit.
- Italic, underline, strikethrough, and text color still work inside the
  header; bold is simply always on there. Per-note font family/size changes
  rescale the header proportionally.

## Implementation

A `restyleHeader()` pass in `StickyTextView`, invoked from:

1. a `didChangeText()` override (every edit),
2. after `RichTextController.loadRTF` (note load / relaunch),
3. after `RichTextController.applyFont` (per-note font or size change).

The pass:

1. Applies the header font (note font × 1.3, bold forced, italic preserved)
   to the first paragraph, and sets header typing attributes when the
   insertion point is in the first paragraph.
2. Demotes any run *outside* the first paragraph whose font size exceeds the
   note's body size back to body size, preserving bold/italic traits. This is
   what un-headers a line pushed down by a newline. Font size is a safe
   discriminator because the app has no per-run size editing — only the
   header is ever oversized.

The text view learns the note's body font size from `applyFont` (and the
note's persisted `fontName`/`fontSize` on load), stored as a property on
`StickyTextView`.

Header styling is baked into the persisted RTF, so persistence, the
Notes-menu `titleSnippet`, and RTF round-tripping are unchanged. No changes
to `StickyGridCore` or the on-disk document format.

## Edge cases

- Empty note: typing attributes start in header style, so the first
  keystroke renders bold/large immediately.
- Bulleted first line: the bullet marker renders header-sized too. Accepted.
- Bold toggle while in the header: re-asserted by the restyle pass,
  effectively a no-op. Accepted.

## Testing

Core unit tests (tiling math, persistence) are unaffected. The feature is
AppKit-side; verify by running the app:

- Type a multi-line note → first line bold/large, body normal.
- Insert a newline mid-header → pushed-down text demotes to body size.
- Delete the first line → next line promotes to header.
- Change per-note font family and size → header rescales.
- Relaunch → styling survives the RTF round-trip; pre-existing notes
  upgrade on load.
