# AI Suggest Title

2026-06-12 · autonomous hourly run

## Problem

Captured notes (clipboard, URL scheme, Services) start with whatever text
came in — often a long content line that becomes an ugly header via the
first-line-header invariant. Hand-written notes drift too. The note already
knows how to ask the model for a color; it should be able to ask for a
title.

## Decision

Add **Suggest Title**: the model reads the note text and proposes a short
title, which is inserted as a **new first line**. The existing first-line
header styling promotes it automatically and demotes the old first line to
body. The old text is untouched and the insert is a single undoable edit.

### Approaches considered

- **Insert as new first line (chosen).** Non-destructive — captured notes
  whose first line is content keep that content. Predictable; one ⌘Z
  reverts.
- Replace the first line. Destroys content whenever line 1 isn't already a
  title, which is exactly the capture case this feature serves. Rejected.
- Sheet with Insert/Replace buttons. More UI than the feature warrants.

## Components

### 1. `NoteAI.suggestTitle(for:)` — Sources/StickyGridApp/NoteAI.swift

`static func suggestTitle(for text: String) async throws -> String`
mirrors `suggestColor(for:)`: one `complete(system:user:)` round trip with
`titleSystemPrompt` (ask for a 2–6 word title, one line, no quotes, no
punctuation, no commentary), then the reply runs through the sanitizer.
Empty after sanitizing → `NoteAIError.badResponse`.

### 2. Sanitizer — `NoteAI.sanitizedTitle(_:)` (the tested unit)

`static func sanitizedTitle(_ reply: String) -> String?`, pure and
nonisolated. Models drift from "one word, no punctuation" instructions
(the color parser already compensates for this), so the sanitizer
normalizes:

- take the first non-empty line of the reply
- strip a leading `Title:` label (case-insensitive)
- strip leading markdown `#` markers
- strip matching surrounding quotes (straight `"` `'` and curly “” ‘’)
- drop a trailing `.`
- collapse internal whitespace runs to a single space, trim ends
- nil when nothing is left

### 3. Apply path — `RichTextController.insertTitleLine(_:)` (tested unit)

Inserts `title + "\n"` at location 0 styled in `bodyFont` + current ink,
through `shouldChangeText`/`didChangeText` so the edit is undoable,
autosave fires, and `restyleHeader()` promotes the new line / demotes the
old one. Works on an empty note too (result is `title + "\n"`), though the
menu path never gets there.

### 4. Wiring — WindowManager + menus

`WindowManager.suggestTitle(on:)` mirrors the non-quiet `suggestColor(on:)`
path exactly: busy guard, empty-text beep, missing-key prompt, `aiBusy`
spinner, `presentAIError` on failure. On success it calls
`viewModel.textController.insertTitleLine(title)`.

- AI menu: "Suggest Note Title" via `@objc aiSuggestTitleNote(_:)`,
  directly after "Suggest Note Color".
- Sparkles menu (NoteToolbarView): "Suggest Title" after "Suggest Color",
  via a new `NoteViewModel.onSuggestTitle` closure wired in WindowManager
  next to `onSuggestColor`.

No new defaults, no quiet path — capture auto-titling can build on this
later if wanted.

## Testing

- `NoteAITitleTests` (pure): pass-through, quote/`#`/`Title:` stripping,
  first-non-empty-line selection, trailing period, whitespace collapse,
  nil on empty.
- `TitleInsertTests` (@MainActor, StickyTextView harness from
  HeaderStylingTests): inserting "Groceries" into "milk\neggs" yields
  "Groceries\nmilk\neggs" with line 1 bold @ header size and "milk"
  demoted to body size — bold survives demotion, matching the existing
  "traits preserved" invariant in HeaderStylingTests; insert into empty
  note yields "Groceries\n"; the edit is undoable via the view's
  undoManager.

Network paths (`suggestTitle`, WindowManager glue) stay untested as with
the other AI features; manual GUI verification deferred to the user.
