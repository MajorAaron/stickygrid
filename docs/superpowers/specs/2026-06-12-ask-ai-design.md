# Ask AI — free-form note transform

Date: 2026-06-12
Status: implemented

## Problem

AI Assist offers three fixed transforms (Summarize, Turn Into Checklist,
Polish Writing). Anything else — "translate to Spanish", "make this more
formal", "expand each bullet into a sentence" — has no path, even though the
Anthropic plumbing (`NoteAI.transform`) is generic.

## Design

One new capability: **Ask AI…** prompts for a free-form instruction and runs
the focused note's text through it, replacing the note text like the presets
do.

### Core (testable headless)

`NoteAIAction` gains an associated-value case:

```swift
enum NoteAIAction: Identifiable, Equatable {
    case summarize, checklist, polish
    case ask(String)            // user-written instruction
    static let presets: [NoteAIAction] = [.summarize, .checklist, .polish]
}
```

- `CaseIterable`/`String` raw values are dropped; menus iterate `presets`
  (the only `allCases` caller was the note toolbar).
- `systemPrompt` for `.ask` keeps the shared sticky-note contract (first line
  is the title, return ONLY plain text) and appends the user's instruction,
  framed so the output contract wins over instruction attempts to change the
  format.
- `id`: stable strings (`"summarize"`, …, `"ask"`); `title`: "Ask AI".

### UI wiring (deferred to manual verification)

- **AI menu**: "Ask AI…" (⌥⌘A) above the presets' separator, targeting
  `WindowManager.aiAskNote(_:)`.
- **Note toolbar sparkles menu**: presets, divider, "Ask AI…" via a new
  `NoteViewModel.onAskAI` callback.
- `WindowManager.promptAskAI(on:)` shows an NSAlert with a text field
  (prefilled from UserDefaults key `AILastAskInstruction`, saved on run),
  sheet-attached to the note panel, then calls the existing
  `runAI(.ask(instruction), on:)`. Empty instruction cancels silently.
  Missing API key falls through to the existing key prompt.

## Tests

`Tests/StickyGridAppTests/NoteAIActionTests.swift`:
- presets are exactly the three fixed actions (no `ask`)
- `.ask` system prompt contains the instruction verbatim
- `.ask` system prompt keeps the shared output contract
- ids are stable and unique across presets + ask

## Out of scope

- Streaming responses, selection-only transforms, instruction history UI.
