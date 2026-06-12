# Markdown Typing Shortcuts — Design

Date: 2026-06-11
Status: Approved (live typing conversion chosen over paste/export support,
markdown-native storage, and convert-on-commit)

## Goal

Type markdown and get formatting instantly, the way Bear, Notion, and Apple
Notes behave. Notes remain rich text (RTF) — markdown is an input method,
not a storage format.

## Scope

In scope:

- Inline styles, converted the moment the closing delimiter is typed:
  `**bold**`, `*italic*`, `~~strikethrough~~`, `` `code` ``.
- List triggers, converted on the space after the marker at the start of a
  plain paragraph: `- ` or `* ` (bullet), `1. ` (numbered), `- [ ] ` /
  `- [x] ` (checkbox).
- Markers vanish on conversion; ⌘Z restores the literal typed text.

Out of scope (possible follow-ups):

- Paste-markdown → formatted conversion, and copy/export as markdown.
- Mid-note `#` headers and block elements (blockquote, code block, divider).
- Underscore emphasis (`_italic_`, `__bold__`) — deliberately excluded; it
  false-positives on snake_case and filenames.
- AI "Turn Into Checklist" emitting real checkbox lines instead of literal
  `- ` text (natural follow-up once checkboxes exist).
- A preference to disable auto-conversion. ⌘Z is the escape hatch.

## Architecture

Two pieces, split so the pattern logic is pure and unit-testable:

1. **`MarkdownTyping.swift` in `StickyGridCore`** — pure functions, no
   AppKit:
   - `inlineMatch(paragraph:caret:)` — given the current paragraph's text
     and caret offset, returns the completed inline pattern ending at the
     caret, if any: style (bold / italic / strike / code), the full range
     including markers, and the content range without them.
   - `listTrigger(linePrefix:)` — given the text from paragraph start to
     caret, returns the list kind just triggered (bullet, numbered with its
     number, checkbox checked/unchecked), if any.
2. **`StickyTextView+Markdown.swift` in the app target** — overrides
   `insertText(_:replacementRange:)`: after `super`, if the typed character
   is a trigger (`*`, `~`, `` ` ``, or space), consult the scanner and apply
   the conversion through the existing `shouldChangeText` →
   `replaceCharacters` → `didChangeText` path, so undo, autosave, and the
   first-line header restyle all fire normally.

## Inline conversion rules

- Conversion triggers when the closing delimiter is typed; scanning covers
  only the current paragraph, only text before the caret.
- Sanity rules, simplified from CommonMark: content non-empty, no space
  directly inside the markers (`** bold**` does not convert), opening marker
  at a word boundary. Longest delimiter wins (`**bold**` is bold, not italic
  with stray asterisks).
- Bold/italic apply via the same `NSFontManager` trait paths as ⌘B/⌘I;
  strikethrough via the existing attribute. No new styling machinery.
- `` `code` `` sets the run in Menlo at the note's body size, keeping the
  note's ink color. No background fill.
- Nothing converts inside an existing code span. Conversions touch only the
  matched run: markers removed, style applied to the content range.
- The first-line header invariant is untouched: conversions change traits
  per-run, and `restyleHeader()` re-asserts header sizing after every edit,
  exactly as it does for toolbar bold today.

## List behavior

All list markers are literal text plus indented paragraph style — the same
pattern as today's bullets, chosen there because it round-trips through RTF
deterministically.

- `- ` / `* ` → existing bullet machinery (`•\t` marker + indent). The
  typed characters are removed.
- `1. ` (any number) → literal `N.\t` marker with the same indent
  treatment. Return continues with previous-number-plus-one. No global
  renumbering when a middle item is deleted — deliberately simple, same
  spirit as the bullet design.
- `- [ ] ` / `- [x] ` → literal `☐\t` / `☑\t` marker. Clicking the glyph
  toggles it — an undoable single-character replacement that does not move
  the caret. No strikethrough on checked text (possible later).
- The existing return-key behavior generalizes from "bullet marker" to a
  marker family: return continues the list with the right next marker
  (`•\t`, `N.\t`, fresh `☐\t`); return on an empty item removes the marker
  and exits the list, exactly like bullets today.
- Triggers fire only at the start of a plain (unmarked) paragraph.

## Undo

Before every conversion the view calls `breakUndoCoalescing()`, so a single
⌘Z immediately after a conversion restores exactly what was typed —
`**bold**` with the asterisks back, `- ` instead of a bullet.

## Persistence

Converted formatting is ordinary rich text baked into the persisted RTF.
No changes to `NoteRecord`, the on-disk document format, or
`RichTextController`'s RTF round-trip.

## Testing

The scanner functions in `StickyGridCore` are pure; unit tests in the
existing `Tests/` target cover:

- Each inline style converts; markers and content ranges are correct.
- Boundary rules: `** bold**`, empty content, mid-word asterisks, unclosed
  markers — none convert.
- Longest-delimiter-wins: `**bold**` → bold.
- List trigger parsing for `- `, `* `, `1. `, `- [ ] `, `- [x] `.
- Next-marker computation for return-key continuation (bullet, numbered
  increment, fresh unchecked checkbox).

The `StickyTextView` glue is verified manually in the running app:

- Type each pattern → converts live; markers vanish.
- ⌘Z immediately after a conversion → literal text restored.
- Patterns on the first line → header sizing preserved.
- Click a checkbox → toggles; ⌘Z untoggles.
- Return inside each list kind → continues; return on empty item → exits.
- Relaunch → formatting survives the RTF round-trip.
