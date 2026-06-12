# Auto-Title on Capture

Captured notes can quietly give themselves an AI title, the way they can
already quietly color themselves. A new AI-menu checkbox, "Auto-Title
Captured Notes" (off by default), makes every capture — URL scheme,
Services, ⇧⌘N clipboard, ⌃⌥N Quick Capture — run the existing Suggest
Title flow without prompts, beeps, or error alerts.

## Why

AI Suggest Title (2026-06-12) gives a note a 2–6 word first line on
demand, and Auto-Color on Capture (2026-06-12) proved the quiet-capture
pattern. Captured text is exactly the kind of note that lacks a usable
title: a pasted paragraph, a shared selection, a quick thought. Titling
it at capture time makes the Notes menu, ⌘F results, and export
filenames immediately readable.

## Behavior

- AI menu gains a second checkbox under "Auto-Color Captured Notes":
  **"Auto-Title Captured Notes"**. State lives in UserDefaults key
  `AIAutoTitleCapture`, default OFF (it spends API tokens per capture).
  Checkmark via the existing `validateMenuItem`.
- When a capture arrives and the rule below passes, the note titles
  itself: a new first line is inserted, the old first line demotes
  intact (same traits-preserved invariant as manual Suggest Title), and
  one undo reverts it.
- The quiet path never beeps, never prompts for an API key, and
  swallows request errors — a failed auto-title just leaves the note as
  captured.
- Plain ⌘N notes are not auto-titled — there is no text at creation.
- If auto-color is also enabled, both run on the same captured note,
  **title first, then color**, sequentially. (Both actions guard on
  `aiBusy`; firing them concurrently would make the second one silently
  bail. Sequential also means the color model reads the final text.)

## Decision rule

`WindowManager.shouldAutoTitle(request:enabled:hasAPIKey:)` —
nonisolated, pure, the tested unit, mirroring `shouldAutoColor`:

- `enabled` — the checkbox is on
- `hasAPIKey` — capture must never prompt, so a missing key disables it
- `!request.hasExplicitTitle` — the caller already chose a title
- request text is non-empty after trimming

## CaptureRequest.hasExplicitTitle (Core)

`stickygrid://new?title=...` folds the title into `text` as the first
line and currently forgets it was explicit. New stored property
`hasExplicitTitle: Bool` (default `false` in the memberwise init, so
existing call sites are untouched):

- `from(url:)` sets it when a non-empty `title` query item was given.
- `from(plainText:)` leaves it `false` — clipboard and Services text
  has no explicit title.

This is the title analog of the color rule's `request.color == nil`.

## Plumbing

- `suggestTitle(on:)` gains a `quietly: Bool = false` parameter exactly
  like `suggestColor(on:quietly:)`: quiet skips the beep, the key
  prompt, and `presentAIError`.
- Both suggest functions refactor into `async` cores
  (`performSuggestTitle` / `performSuggestColor`) with thin
  fire-and-forget wrappers, so `createNote(from:activate:)` can chain
  them in one Task: `await title; await color`.
- `createNote` evaluates both `shouldAutoTitle` and `shouldAutoColor`
  up front, then runs whichever passed.
- Menu: `MainMenuBuilder` adds the item next to Auto-Color;
  `WindowManager.toggleAutoTitleCapture(_:)` and an
  `autoTitleCaptureEnabled` static mirror the color versions;
  `validateMenuItem` handles the new selector.

## Testing

`AutoTitleCaptureTests` mirrors `AutoColorCaptureTests`:

- rule passes when enabled + keyed + no explicit title + non-empty text
- setting off wins over everything
- missing key means no auto-title (capture never prompts)
- `hasExplicitTitle` request is respected
- empty/whitespace text has nothing to title
- `AIAutoTitleCapture` round-trips through UserDefaults, defaults off

`CaptureRequestTests` (Core) gains:

- URL with `title=` → `hasExplicitTitle == true`
- URL with only `text=` → `false`
- bare `stickygrid://new`, empty `title=` → `false`
- `from(plainText:)` → `false`

The network call and the insert path are already covered by
`NoteAITitleTests` and `TitleInsertTests`; the sequential
title-then-color chain is glue and is verified manually.

## Out of scope

- A shared "auto-enhance" toggle covering both color and title — the
  two checkboxes stay independent.
- Auto-title for ⌘N, paste, drop, or markdown import (imports usually
  already have a heading as line 1).
- Retitling when the note later changes.
