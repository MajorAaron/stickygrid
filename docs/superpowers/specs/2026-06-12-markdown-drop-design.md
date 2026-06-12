# Markdown drag-and-drop — design

Date: 2026-06-12
Status: implemented

## Problem

Notes can already be created from markdown via paste (⌘V), File → Import
Markdown… (⇧⌘I), and capture surfaces. But the most direct cross-app gesture —
dragging — still falls back to NSTextView defaults: dropping a `.md` file onto
a note inserts a file icon or path, and dropping markdown text from another
app inserts the raw marker literals (`**bold**`, `- item`) unconverted.

## Behavior

Two drop cases on any note's text view:

1. **Markdown files** (`.md` / `.markdown`, case-insensitive extension):
   each dropped file becomes its own new styled note via the existing
   `WindowManager.importNote(from:)` path — identical result to
   File → Import Markdown…. Non-markdown files in the same drop are ignored;
   if the drop contains at least one markdown file, the drop is consumed.
2. **Plain markdown text** (no RTF/RTFD flavor on the drag pasteboard, no
   file URLs, and `MarkdownImport.detectsMarkdown` fires): the text converts
   to styled runs and native list markers at the drop point via the existing
   `insertMarkdown` — identical result to markdown paste.

Everything else (rich-text drags, plain text without markdown, non-markdown
files) keeps NSTextView's default drop behavior.

## Design

- `StickyTextView.DropAction` (`importFiles([URL])` / `insertMarkdown(String)`
  / `passthrough`) and `static dropAction(for: NSPasteboard) -> DropAction`
  in a new `StickyTextView+Drop.swift` — the pasteboard classification is the
  tested unit, mirroring how the paste override classifies
  `NSPasteboard.general`.
- `performDragOperation` switches on the action; `draggingEntered/Updated`
  and `prepareForDragOperation` answer `.copy`/true for the file case so
  file drags are accepted even though the view never imports attachments
  (`importsGraphics` is false). Text drops use
  `characterIndexForInsertion(at:)` to place the caret before converting.
- File drops route out of the view layer through
  `StickyTextView.onDropMarkdownFiles`, set in `RichTextEditor.makeNSView`
  from a new `NoteViewModel.onImportFiles` closure, which WindowManager wires
  to `importNote(from:)` — same ownership pattern as `onShare`.

## Testing

- Pasteboard classification: file vs text vs passthrough, extension
  case-insensitivity, mixed-file drops, Finder-style URL+string drops,
  RTF passthrough (`DropActionTests`).
- Behavior through `performDragOperation` with a stub `NSDraggingInfo`:
  file drops fire the callback and consume the drop; markdown text drops
  insert styled runs (`MarkdownDropTests`).
- Manual GUI verification (drag from Finder / another app) deferred to the
  user, as with prior drop-adjacent features.
