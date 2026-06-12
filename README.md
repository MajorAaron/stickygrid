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
- Markdown typing shortcuts: `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``
  convert as you type; `- `, `1. `, and `- [ ] ` start bullet, numbered, and
  clickable-checkbox lists, and `> ` starts a blockquote with a quote bar.
  Markers vanish; ⌘Z brings them back. Return continues lists and quotes;
  return on an empty item exits.
- Markdown paste: ⌘V a block of markdown (from a chat reply, a README, another
  notes app) and the same styles, lists, checkboxes, quotes, and headings
  convert on the way in. Plain text without markdown pastes untouched.
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
- Capture from anywhere: a global ⌃⌥N Quick Capture palette, a `stickygrid://`
  URL scheme, a `sticky` command-line tool, a Services menu entry, and ⇧⌘N
  for the clipboard (see below)
- AI Assist: summarize a note, turn it into a checklist, or polish the writing
  (see below)
- Find in Notes (⌘F) — a Spotlight-style palette that live-searches every
  note as you type (case- and accent-insensitive), title matches ranked
  first. ↑/↓ moves the highlight; Return jumps to the note, selects the
  hit, and flashes the find indicator
- Share & export: send a note anywhere as markdown (see below)
- Import Markdown… (⇧⌘I): turn `.md` files from any other app into styled
  sticky notes (see below)
- Drag and drop: drop `.md` files from Finder onto any note to make new
  styled notes, or drag markdown text from another app into a note and it
  converts on the way in (see below)

## Share a note with other apps

Every way text gets *into* StickyGrid has a twin for getting it *out*. All
three serialize the note to markdown — formatting, lists, and checkboxes
round-trip: the title becomes an `# H1`, bold/italic/strike/code become
`**`/`*`/`~~`/`` ` ``, and bullets, numbered items, and checkboxes become
`- `, `1. `, `- [ ] `, and `- [x] `.

- **Share button** (the export arrow on the hover toolbar, or
  File → Share Note) — opens the macOS share sheet, so a sticky can jump
  straight to Mail, Messages, Apple Notes, or any app that accepts text.
- **Copy as Markdown (⌥⌘C)** — puts the markdown on the clipboard, ready to
  paste into Slack, GitHub, Obsidian, or a commit message.
- **Export Note as Markdown… (⇧⌘E)** — writes a `.md` file named after the
  note's title.

## Capture notes from other apps

Six ways to get text into a sticky without switching to StickyGrid first:

- **Quick Capture (⌃⌥N from anywhere)** — a system-wide hotkey that works in
  any app, no Accessibility or Input Monitoring permission needed. A small
  floating palette appears over whatever you're doing: type the note, click a
  color dot (your last choice is remembered), and press ⌘↩. The sticky is
  created *without* switching apps — you stay right where you are. Esc
  cancels; clicking away keeps the draft for the next summon. Remap the
  shortcut with

  ```bash
  defaults write com.aaronmajor.stickygrid QuickCaptureHotKey "cmd+shift+space"
  ```

  (modifiers `cmd`/`ctrl`/`alt`/`shift` joined with `+`, then a letter,
  digit, or `space`; the value `off` disables it). Also in the menu as
  File → Quick Capture.
- **URL scheme** — from Shortcuts, Raycast, Alfred, a browser bookmarklet, or
  `open` in a terminal:

  ```bash
  open "stickygrid://new?title=Groceries&text=milk%0Aeggs&color=pink"
  ```

  `text` (alias `body`) is the percent-encoded note body, `title` becomes the
  first line (auto-styled as the header), and `color` is one of the eight
  palette names. A bare `stickygrid://new` opens an empty note.
- **Shell / scripts — the `sticky` command** — a tiny CLI that builds the
  capture URL for you (percent-encoding included) and opens it, so notes
  are one pipe away from any terminal, Raycast/Alfred script, cron job, or
  Shortcuts "Run Shell Script" action:

  ```bash
  sticky Buy milk
  git log --oneline -5 | sticky --title "Release notes" --color blue
  sticky --print "hi"        # print the stickygrid:// URL instead of opening
  ```

  Words join into the body; with no words the body is read from piped
  stdin; `--title`/`-t` sets the first line and `--color`/`-c` one of the
  eight palette names.

  The CLI also reads your notes back out (read-only — safe while the app
  is running):

  ```bash
  sticky list               # one line per note: id, title, color
  sticky cat groceries      # print a note by title words or id prefix
  sticky cat -m groceries   # ...as markdown: headings, bold, lists, quotes
  ```

  `cat` matches an id prefix or a title substring and insists on a unique
  hit (ambiguous queries list the candidates). `-m`/`--markdown` prints
  the note with its styling intact — the same serialization as ⌥⌘C — so
  `sticky cat -m groceries | pbcopy` moves a styled note into any app
  that speaks markdown. To capture a note whose body starts with the
  word "list" or "cat", escape with `sticky -- list`.
  Build and install it with:

  ```bash
  swift build -c release --product sticky
  cp .build/release/sticky /usr/local/bin/
  ```
- **Services menu** — select text in any app, then
  *(app menu) → Services → New Sticky Note from Selection*.
- **Clipboard** — ⇧⌘N (File → New Note from Clipboard) pastes whatever is on
  the clipboard into a new note.
- **Markdown files** — ⇧⌘I (File → Import Markdown…) turns each selected
  `.md` file into its own note. Headings, bold/italic/strike/code, bullets,
  numbered lists, and checkboxes all convert to the native styled
  representation — the exact inverse of Export Note as Markdown, so notes
  exported from another machine (or written in Obsidian, exported from a chat,
  generated by a script) come in looking hand-typed.
- **Drag and drop** — drop `.md`/`.markdown` files from Finder (or any app)
  onto an existing note and each file becomes its own styled note, exactly
  like Import Markdown…. Dragging a *text selection* that contains markdown
  into a note converts it to styled runs at the drop point, exactly like
  markdown paste; rich-text drags and plain text without markdown drop
  normally.

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
