# StickyGrid — Design Spec

Date: 2026-06-10
Status: Approved

## What it is

A native macOS Stickies-style notes app. Lightweight floating note windows live directly on the
desktop, each independently colored and styled, with a signature one-click button that tiles all
notes into a screen-filling mosaic (like Glassnote's tiled layout).

## User-approved decisions

- **Platform**: Native Mac app, SwiftUI + AppKit hybrid. AppKit owns the windows (precise control
  over frames, levels, tiling animation); SwiftUI renders the note content and toolbar.
- **Name**: StickyGrid.
- **Visual style**: classic opaque pastel sticky colors (~8 swatches: yellow, pink, blue, green,
  purple, orange, gray, white). Not translucent glass.
- **Tiling**: mosaic fill — notes tile edge-to-edge filling the screen's visible area, with sizes
  weighted by each note's current area. Triggered by a toolbar button or ⌘T. Only affects notes on
  the active screen. Windows animate simultaneously into place.
- **V1 features**:
  - Create / edit / delete notes (close = delete, with confirmation if the note has content)
  - Per-note color and font family/size
  - Rich text: bold ⌘B, italic ⌘I, underline ⌘U, strikethrough, bullet lists
  - Pin-on-top per note (window floats above all apps)
  - Autosave (debounced ~1 s) + full restore on relaunch (frames, stacking order, pin state)
  - Standard Dock app with real menus; a Notes menu lists every note so none get lost
  - Stretch goal (not v1): interactive checkboxes
- **Persistence**: local only — `~/Library/Application Support/StickyGrid/` containing `notes.json`
  (id, frame, colorID, fontName, fontSize, pinned, zOrder, titleSnippet per note) plus one
  `<uuid>.rtf` per note. No cloud, no database.

## Architecture

Two-target Swift Package plus a bundle script:

- **StickyGridCore** (library, Foundation/CoreGraphics only, fully unit-testable):
  `NoteRecord` (Codable model), `NoteColor` (8 pastel color IDs), `TreemapLayout` (pure tiling
  math — recursive weighted binary split), `NotesDocument` (versioned JSON wrapper).
- **StickyGridApp** (executable, AppKit + SwiftUI): manual `NSApplication` bootstrap,
  `AppDelegate`, programmatic menus, `NoteStore` (data + debounced autosave + corruption
  recovery), `WindowManager` (one borderless `NotePanel` per note; create/restore/delete/tile),
  `RichTextEditor` (TextKit 1 `NSTextView` wrapped for SwiftUI), hover-fade `NoteToolbarView`.
- **Scripts/build-app.sh**: assembles and ad-hoc codesigns a real `StickyGrid.app` from the CLI.

## Error handling

Never crash on load: a corrupted `notes.json` is renamed to `notes.json.corrupt-<timestamp>` and
the app starts empty; a corrupted/missing `.rtf` is backed up and that note opens empty. Saves are
atomic with 3 retries; unsaved changes at quit raise a "Quit Anyway / Cancel" warning.

## Testing

- `swift test`: treemap invariants (non-overlap, bounds coverage, weight proportionality, min-size
  clamping, order preservation) and persistence round-trip/corruption — no UI required.
- Manual smoke checklist via `open build/StickyGrid.app`: focus, drag vs text-select, resize,
  formatting + undo, pin floats over other apps, tiling animation, quit/relaunch fidelity,
  corruption recovery.
