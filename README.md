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
