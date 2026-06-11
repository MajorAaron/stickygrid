# StickyGrid

A native macOS sticky-notes app, like Apple Stickies with one superpower: click the
tile button (or press ⌘T) and every note animates into an edge-to-edge mosaic that
fills your screen.

![pastel sticky notes tiled in a mosaic]

## Features

- Each note is its own lightweight floating window — drag it anywhere by its edges
  or header, resize from any edge
- 8 classic pastel colors, switchable per note from the hover toolbar
- Rich text: **bold** ⌘B, *italic* ⌘I, underline ⌘U, strikethrough ⇧⌘X,
  bullet lists ⇧⌘L (with automatic continuation on return)
- The first line of every note is its title — automatically bold and larger,
  so a wall of notes stays scannable
- Per-note font family and size
- Pin a note to float above every other app
- One-click mosaic tiling (⌘T) — notes fill the screen, sized by their current areas
- Autosaves about a second after you stop typing; everything (positions, stacking
  order, colors, pins, formatting) restores exactly on relaunch
- Local only: notes live in `~/Library/Application Support/StickyGrid/`. No cloud,
  no accounts, no database.
- Closing a note deletes it (with a confirmation if it has text), like real Stickies.
  The Notes menu lists every note so none get lost.
- Per-note text ink: six marker colors plus an auto ink tuned to each background
- Capture from anywhere: a `stickygrid://` URL scheme, a Services menu entry,
  and ⇧⌘N for the clipboard (see below)
- AI Assist: summarize a note, turn it into a checklist, or polish the writing
  (see below)

## Capture notes from other apps

Three ways to get text into a sticky without switching to StickyGrid first:

- **URL scheme** — from Shortcuts, Raycast, Alfred, a browser bookmarklet, or
  `open` in a terminal:

  ```bash
  open "stickygrid://new?title=Groceries&text=milk%0Aeggs&color=pink"
  ```

  `text` (alias `body`) is the percent-encoded note body, `title` becomes the
  first line (auto-styled as the header), and `color` is one of the eight
  palette names. A bare `stickygrid://new` opens an empty note.
- **Services menu** — select text in any app, then
  *(app menu) → Services → New Sticky Note from Selection*.
- **Clipboard** — ⇧⌘N (File → New Note from Clipboard) pastes whatever is on
  the clipboard into a new note.

The URL scheme and Services entry register when the built `StickyGrid.app` is
first launched (they're declared in its Info.plist, so `swift run` alone won't
register them).

## AI Assist

The ✨ sparkles button on the hover toolbar (or the **AI** menu) runs the
focused note through one of three transforms:

- **Summarize** — condenses the note to its essential points
- **Turn Into Checklist** — one `- ` task per line, compound items split
- **Polish Writing** — fixes spelling and grammar, preserving tone and structure

The first line stays the note's title, the result replaces the body in the
note's current font and ink, and the swap is undoable with ⌘Z.

Transforms call the Anthropic API directly (model `claude-opus-4-8` by
default; override with `defaults write` key `AIModel`). The API key is read
from the `ANTHROPIC_API_KEY` environment variable, or from
`~/.config/stickygrid/anthropic-api-key` — set it in-app via
**AI → Set Anthropic API Key…**. Nothing is sent anywhere until you run a
transform.

## Build & run

Requires macOS 15+ and Xcode command-line tools.

```bash
./Scripts/build-app.sh     # builds release + assembles build/StickyGrid.app
open build/StickyGrid.app
```

Dev loop:

```bash
swift run StickyGrid       # run from CLI
swift test                 # unit tests (tiling math + persistence)
```

## Architecture

- `Sources/StickyGridCore` — pure, UI-free library: note models, versioned JSON
  document, and the treemap tiling algorithm (recursive weighted binary split).
  Fully covered by `swift test`.
- `Sources/StickyGridApp` — AppKit + SwiftUI executable: borderless `NSWindow`
  per note, TextKit 1 `NSTextView` for rich text (persisted as RTF), SwiftUI
  hover toolbar, programmatic menus.
- `Scripts/build-app.sh` — assembles and ad-hoc signs the `.app` bundle.

Design spec: `docs/superpowers/specs/2026-06-10-stickygrid-design.md`.
