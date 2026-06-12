# Share & Export — design

StickyGrid can capture notes from anywhere (URL scheme, Services, clipboard,
Quick Capture) but has no way to get a note *out*. This feature adds the
outbound half: serialize a note back to markdown and hand it to the system.

## Surfaces

- **Share button** on the hover toolbar (`square.and.arrow.up`) — opens the
  standard `NSSharingServicePicker` (Mail, Messages, Notes, …) with the note's
  markdown text.
- **File → Copy as Markdown** (⌥⌘C) — puts the markdown on the clipboard.
- **File → Export Note as Markdown…** (⇧⌘E) — save panel, writes a `.md` file
  named after the note's title.
- **File → Share Note** — menu twin of the toolbar share button.

All four act on the front note and serialize through one code path.

## Markdown serialization (the inverse of markdown typing)

`MarkdownExport` in StickyGridCore is a pure serializer mirroring
`MarkdownTyping`:

- Input: paragraphs of styled `Run`s (`text`, `bold`, `italic`,
  `strikethrough`, `code`). The app layer builds runs from `NSTextStorage`
  font traits; Core stays AppKit-free.
- Line markers (the app's literal list representation) reverse-map:
  `•\t` → `- `, `N.\t` → `N. `, `☐\t` → `- [ ] `, `☑\t` → `- [x] `.
  Parsing reuses `MarkdownTyping.LineMarker`.
- Inline styles wrap their runs: code → `` ` `` (wins over other flags,
  matching the typing direction where code spans stay literal),
  bold+italic → `***`, bold → `**`, italic → `*`, strikethrough → `~~`
  (outside bold/italic). Underline has no markdown equivalent and is dropped.
- Adjacent runs with identical flags merge first, so styling applied in
  pieces still emits one delimiter pair. Leading/trailing whitespace inside a
  styled run is hoisted outside the delimiters (`**bold **` is invalid
  markdown).
- The first paragraph is the note's title: it exports as `# Title` unless it
  is a list line or empty. The app layer clears the bold flag on that
  paragraph — its boldness is the auto-header style, not user emphasis.
- No escaping of literal `*`/`~`/`` ` `` in text — same pragmatic stance as
  the typing direction.

## App glue

`RichTextController.markdownText()` walks the storage paragraph by paragraph,
splits each into attribute runs (bold/italic from `NSFontManager` traits,
code = font name prefixed "Menlo", strikethrough from the attribute), and
feeds `MarkdownExport`.

`WindowManager` owns the three actions, mirroring the AI Assist pattern
(front-note lookup, beep when no note). Export's save panel suggests
`<title>.md`, sanitized of `/` and `:`.

## Testing

- Core: table of serializer cases (styles, merging, whitespace hoisting,
  markers, heading rule, empty paragraphs).
- App: end-to-end test — type into a real `StickyTextView` (existing test
  harness), serialize, assert markdown — covering trait→Run extraction and
  the title bold-drop.
