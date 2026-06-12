# Markdown Blockquotes — Design

Date: 2026-06-12
Status: Approved (quote bar as a LineMarker, chosen over paragraph-style-only
rendering and over a styled/dimmed quote body)

## Goal

`> ` typed at the start of a line becomes a blockquote, the way it already
works for `- `, `1. `, and `- [ ] `. Quotes round-trip through every
markdown surface the app has: typing, paste, drag-and-drop, file import,
Copy as Markdown, and export.

This is the "quotes" half of the typing spec's deferred block elements.
Mid-note `#` headings stay on the backlog: they collide with the first-line
header invariant (restyleHeader demotes any oversized run below line 1), so
they need their own design pass.

## Native representation

A quote is a `MarkdownTyping.LineMarker` case, exactly like bullets:

- Literal marker `▎\t` (U+258E LEFT THREE EIGHTHS BLOCK + tab) at the
  paragraph start, plus the shared list indent. The block glyph renders as
  a solid vertical bar in the note's ink — a quote bar, drawn by the text
  system itself.
- The quote body is unstyled. No dimming, no italics — the bar and indent
  carry the meaning, and the body stays free for inline markdown.

Literal-marker-plus-indent is the established representation because it
round-trips RTF deterministically; quotes inherit every behavior the marker
family already has for free:

- Return continues the quote with a fresh `▎\t` (markdown's multi-line
  quote, typed naturally).
- Return on an empty quote line removes the bar and exits, like lists.
- Pasted/dropped/imported markdown `> ` lines become native quote lines via
  the shared `MarkdownImport` → `insertMarkdown` path.
- Export and Copy as Markdown emit `> ` via `MarkdownExport`'s generic
  marker stripping.

## Changes

All in `StickyGridCore`; the app layer is generic over `LineMarker` and
needs no changes.

1. `MarkdownTyping.LineMarker` gains `.quote`:
   - `literal` / `continuationLiteral` → `"▎\t"` (quotes repeat on return).
   - `parse` recognizes the `▎\t` prefix.
2. `MarkdownTyping.listTrigger` maps the line prefix `"> "` → `.quote`.
   Trigger rules match lists: fires only when `> ` is the entire prefix of
   a plain paragraph. `>` without a space, or mid-line, stays literal.
3. `MarkdownImport.lineMarker` maps a `"> "` line prefix → `.quote` with
   the rest of the line parsed for inline spans. `>` without a space stays
   literal text; nested `>>` is out of scope.
4. `MarkdownExport.markdownPrefix` maps `.quote` → `"> "`. The existing
   marker branch already beats the first-line `# ` heading rule, so a note
   whose first line is a quote exports as `> …`, not `# ▎…`.

## Out of scope

- Nested quotes (`>> `), lazy continuation (`>` without space).
- Dimmed or italic quote body styling.
- Mid-note `#` headings (backlog; see above).

## Testing

Pure-core unit tests, mirroring the existing marker suites:

- `listTrigger("> ")` → `.quote`; `">"`, `">  "`, and mid-line stay nil.
- `LineMarker.parse("▎\t…")` → `.quote`; literal and continuation are
  `"▎\t"`.
- `MarkdownImport.parse("> quoted *text*")` → `.quote` marker with italic
  run; `detectsMarkdown` is true for a quote-only string; `">no space"` is
  literal.
- `MarkdownExport` emits `> …` for a quote line, including when it is the
  first line (no `# ` heading prefix).
- Round-trip: markdown with a quote block survives import → export.

The view glue (trigger-on-space, return continuation, exit-on-empty) is the
existing tested-by-use marker machinery; manual GUI verification is
deferred to the user, as with prior features.
