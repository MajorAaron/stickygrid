# Markdown File Import — design

2026-06-11. Completes the markdown round-trip: typing shortcuts (outbound
styling), Copy/Export as Markdown (outbound files), Markdown Paste (inbound
text), and now **inbound files** — File → Import Markdown… turns `.md` files
from any other app into styled sticky notes.

## Behavior

- **File → Import Markdown…** (⇧⌘I) opens an `NSOpenPanel` with multiple
  selection, filtered to `.md` / `.markdown` / plain-text files.
- Each selected file becomes one new note at the usual cascade position:
  markdown headings, bold/italic/strikethrough/code spans, bullets, numbered
  lists, and checkboxes convert to the native styled representation.
- The note's title snippet is the first line of the *converted* text (markdown
  syntax stripped), capped at 40 chars like every other path.
- Files that are unreadable or contain only whitespace are skipped. If nothing
  imports, the app beeps (same convention as other no-op menu actions).
- Imported notes persist immediately (`markTextChanged`), like captured notes.

## How

Reuse over reimplementation: the paste feature's `StickyTextView.insertMarkdown`
already converts markdown to attributed text with the exact marker literals,
indentation, and fonts the editor produces when typing. A **scratch
StickyTextView** (never added to a window — the same trick the paste tests use)
renders the file's markdown, and its text storage serializes to RTF:

- `WindowManager.rtf(fromMarkdown:record:)` — scratch view configured with the
  record's font/ink/color, `insertMarkdown(content)`, storage → RTF `Data`.
- `WindowManager.openWindow` gains an `initialRTF: Data?` parameter; the
  existing plain-text capture path converts to RTF at the call site
  (`createNote`), so both paths share one loading mechanism.
- The auto-header is applied by `restyleHeader()` when the editor loads the
  RTF, so a leading `# Heading` becomes the header line for free.

## Testing

`Tests/StickyGridAppTests/MarkdownFileImportTests.swift`:
1. RTF from markdown renders marker literals + styled runs (string + traits).
2. RTF loads into an editor and round-trips back to the same markdown.
3. Record font/size is respected in the produced RTF.
4. Title snippet derivation strips markdown (first converted line, 40 cap).

Open-panel interaction itself is manual-verification (deferred to the user, as
with previous UI surfaces).

## Out of scope

- Finder "Open With" / document-type registration (needs Info.plist work the
  SwiftPM app build doesn't model well).
- Drag-and-drop of `.md` files onto notes (separate backlog item).
- Front-matter (YAML) handling — imported verbatim as text for now.
