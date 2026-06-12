# Markdown paste import — design

StickyGrid can now serialize a note *out* to markdown (`MarkdownExport`), and
live typing converts markdown syntax as you type — but pasting a block of
markdown (from a chat reply, a README, another notes app) lands as literal
`**asterisks**` and `- dashes`. This feature completes the round-trip:
pasting markdown converts it to styled runs and native list markers.

## Behavior

- **Paste (⌘V)** with plain text on the pasteboard: if the text contains any
  markdown constructs (inline styles, list/checkbox markers, headings), it is
  converted on insert — styles applied, marker literals swapped for the app's
  native ones (`- ` → `•\t`, `N. ` → `N.\t`, `- [ ] ` → `☐\t`,
  `- [x] ` → `☑\t`), heading `#`s stripped (the auto first-line header
  handles title sizing; non-first heading lines render bold).
- Text with **no** markdown constructs pastes exactly as before (falls
  through to the default paste).
- Pasteboards carrying rich text (RTF) keep the default paste — markdown
  conversion is only attempted for plain-text pastes.
- One ⌘Z undoes the whole paste, restoring the literal markdown is not
  needed — undo removes the pasted text entirely (standard paste semantics).

## Core: `MarkdownImport` (the inverse of `MarkdownExport`)

Pure parser in StickyGridCore, AppKit-free:

- Input: a markdown string. Output: `[Line]`, where each `Line` has an
  optional `MarkdownTyping.LineMarker` (reusing the existing type) and
  `[MarkdownExport.Run]` (reusing the existing run type — same flags:
  bold/italic/strikethrough/code).
- Line prefixes: `- ` / `* ` → bullet, `N. ` → numbered(N),
  `- [ ] ` / `- [x] ` (and `* [ ] `, case-insensitive x) → checkbox.
  `#`–`######` + space → heading: prefix stripped, all runs bold.
- Inline spans inside a line: `` `code` `` (wins; inner markup stays
  literal), `***bold italic***`, `**bold**`, `*italic*`, `~~strike~~`.
  Same validity rules as `MarkdownTyping.inlineMatch`: no whitespace just
  inside the delimiters, opener at a word boundary. Unmatched or invalid
  delimiters stay literal text.
- `detectsMarkdown(_:)` — true when parsing found any marker, heading, or
  inline span; the app uses it to decide convert-vs-plain paste.

## App: paste glue on `StickyTextView`

- `paste(_:)` override: only when the pasteboard's best type is plain text
  and `MarkdownImport.detectsMarkdown` fires, build an
  `NSAttributedString` from the parsed lines (typing attributes as the base;
  bold/italic via font traits, code via Menlo at the run's size, strike via
  attribute — the same mapping the typing converter uses) and insert through
  `shouldChangeText`/`didChangeText` so undo, autosave, and the header
  restyle fire normally. List lines get the standard list indent.
- Marker literals + indent match `applyListMarker`, so continuation on
  return and checkbox clicking work on pasted lists with zero extra code.

## Testing

- Core: `MarkdownImportTests` — line markers, headings, inline styles,
  literal fallbacks, detection; round-trip property: `markdown(parse(md))`
  re-serializes to the same string for canonical inputs.
- App: end-to-end paste into a `StickyTextView` via the real pasteboard
  path, asserting storage text + font traits, and `markdownText()`
  round-trip equality.
