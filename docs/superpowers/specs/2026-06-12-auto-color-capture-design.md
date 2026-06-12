# Auto-Color on Capture — captured notes color themselves

Date: 2026-06-12
Status: implemented

## Problem

Capture paths (stickygrid://new, Services, ⇧⌘N clipboard, ⌃⌥N Quick Capture)
drop everything into default yellow unless the URL names a color explicitly.
The AI Suggest Color feature already maps content → palette color, but it is
manual: the user has to focus the note and ask. Captured notes are exactly the
ones the user is *not* looking at — Quick Capture intentionally leaves them in
the background — so they accumulate uncolored.

## Design

When a note is created through `WindowManager.createNote(from:activate:)` and
auto-color is enabled, the note quietly recolors itself via the existing
`NoteAI.suggestColor(for:)` once the reply lands. Capture must never
interrupt: no beeps, no key prompts, no error alerts — on any failure the
note simply stays yellow.

### Decision rule (testable headless)

`WindowManager.shouldAutoColor(request:enabled:hasAPIKey:)` — nonisolated,
pure. True only when ALL hold:

- the setting is enabled,
- an API key is available (otherwise we'd have to prompt — never during capture),
- the request carries no explicit color (`stickygrid://new?...&color=pink`
  means the caller already chose; respect it),
- the request text is non-empty after trimming (nothing to read).

### Setting

- `WindowManager.autoColorCaptureEnabled` — static Bool backed by UserDefaults
  key `AIAutoColorCapture`, default **off** (it spends API tokens on every
  capture; the user opts in).
- AI menu: "Auto-Color Captured Notes" checkbox under "Suggest Note Color",
  targeting `toggleAutoColorCapture(_:)`; checkmark state via
  `NSMenuItemValidation`.

### Wiring (deferred to manual verification)

- `createNote(from:activate:)` consults the decision rule after opening the
  window and, when true, calls the quiet path.
- `suggestColor(on:quietly:)` — the existing manual path gains a `quietly`
  flag: quiet skips the beep/key-prompt guards (already pre-checked) and
  swallows errors instead of presenting them. Success path is shared:
  set `viewModel.colorID`, `appearanceChanged(id)` persists + repaints.

## Tests

`Tests/StickyGridAppTests/AutoColorCaptureTests.swift`:
- all conditions met → true
- disabled → false
- no API key → false
- request has explicit color → false
- empty / whitespace-only text → false
- `autoColorCaptureEnabled` round-trips through UserDefaults and defaults
  to false when the key is absent

## Out of scope

- Auto-color on plain ⌘N notes (no text yet at creation time), AI title
  suggestion, re-coloring on later edits, batching multiple captures into
  one request.
