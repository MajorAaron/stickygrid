# AI Suggest Color — content-aware note color

Date: 2026-06-12
Status: implemented

## Problem

Notes pile up in default yellow. The palette exists, but picking a color per
note is manual housekeeping. The AI layer already reads note text for
transforms; it can just as well pick a fitting color (deadline → orange,
grocery list → green, idea → purple), making the grid scannable for free.

## Design

One new capability: **Suggest Color** sends the focused note's text to the
model, which answers with one of the eight `NoteColor` names; the note is
recolored and persisted exactly as if the user had tapped that swatch.

Unlike every existing AI action, the result is a `NoteColor`, not replacement
text — so this is a sibling of `NoteAI.transform`, not a `NoteAIAction` case.

### Core (testable headless)

In `NoteAI.swift` (app layer):

- `NoteAI.colorSystemPrompt` — names all eight `NoteColor` raw values
  (derived from `NoteColor.allCases`, so a new color can't be forgotten),
  gives one-line vibes for each, and demands a one-word reply.
- `NoteColor(aiReply:)` — failable init parsing a model reply into a color:
  case-insensitive, tolerates punctuation/explanations, picks the color
  mentioned **earliest** when several appear ("orange, not yellow" → orange),
  accepts the "grey" spelling, returns nil when no color is named.
- `NoteAI.suggestColor(for:)` — async; shares the Messages-API request path
  with `transform` via an extracted `complete(system:user:)` helper, parses
  with `NoteColor(aiReply:)`, throws `.badResponse` on an unparseable reply.

### UI wiring (deferred to manual verification)

- **AI menu**: "Suggest Note Color" below the three text presets, targeting
  `WindowManager.aiSuggestColorNote(_:)`.
- **Note toolbar sparkles menu**: "Suggest Color" with the presets, via a new
  `NoteViewModel.onSuggestColor` callback.
- `WindowManager.suggestColor(on:)` mirrors `runAI`: guards empty text /
  busy / missing key, sets `aiBusy`, then on success sets
  `viewModel.colorID` and calls `appearanceChanged(id)` (persist + repaint).
  Errors reuse `presentAIError`.

## Tests

`Tests/StickyGridAppTests/NoteAIColorTests.swift`:
- bare name parses ("green" → .green)
- punctuation/casing tolerated ("  Purple." → .purple)
- verbose reply parses ("I'd pick blue because…" → .blue)
- earliest mention wins ("orange, not yellow" → .orange)
- "grey" maps to .gray
- garbage returns nil ("teal", "")
- colorSystemPrompt names every NoteColor raw value and demands one word

## Out of scope

- Auto-color on note creation/capture (could ride this later), AI title
  suggestion, recoloring multiple notes at once.
