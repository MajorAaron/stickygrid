# sticky export — bulk markdown export of the whole store

**Date:** 2026-06-12
**Status:** Approved (automated run — decisions made autonomously)

## Problem

The shell suite reads and writes single notes (`sticky`, `sticky list`,
`sticky cat -m`), but there is no way to get *all* notes out at once. A
folder of `.md` files is the lingua franca of every other notes tool —
Obsidian vaults, backups, grep, git. One command should produce it.

## Goals

- `sticky export <dir>` — write one markdown file per note into `<dir>`,
  creating the directory if needed. Styles survive via the same
  `MarkdownExport` walk that `cat -m` uses.
- Filenames derived from note titles, deterministic, collision-safe.
- Naming logic tested in StickyGridCore; the CLI stays glue.
- Read-only on the store: safe while the app is open.

## Non-goals (YAGNI)

- App-side File → Export All Notes… menu (backlog — the CLI covers the
  scripting/backup case; a GUI surface can reuse `NoteExport` later).
- Round-trip import of a folder (drag-and-drop and ⇧⌘I already import
  .md files).
- Front-matter / metadata sidecars (color, pin, frame stay in the store).
- Incremental/sync export — every run rewrites every file.

## CLI surface

```
sticky export <dir>         # one .md per note, creates <dir> if missing
```

- Recognized only when the **first** argument is exactly `export`
  (`sticky -- export` still captures the word "export", matching list/cat).
- A leading `--` after `export` is skipped so a directory may start with
  a dash: `sticky export -- -odd-dir`.
- No directory → usage error (exit 64). More than one positional → usage
  error naming the extra argument (paths with spaces arrive as one
  shell-quoted argument, so a second positional is always a mistake).

## Filenames (Core: `NoteExport.entries(for:)`)

- Order: pinned first, then `zOrder` ascending — the same sort as `list`
  (factored into `NoteListing.sorted(_:)` and shared). Order matters only
  for deterministic collision suffixes.
- Base name: `titleSnippet`, with `/` and `:` each replaced by `-`,
  whitespace runs collapsed to single spaces, trimmed (also of leading
  dots so files never hide), capped at 60 characters. Empty → `Untitled`.
- Collisions (case-insensitive, APFS default): first note keeps
  `Base.md`, later ones get `Base-<id8>.md` (id8 = first 8 hex of the
  UUID, same as `list`).

## CLI behavior

- Empty store → print `no notes`, exit 0, create nothing.
- For each entry: read `<id>.rtf` via the document-reading
  `NSAttributedString` initializer (the `init?(rtf:)` shortcut breaks
  headless — known gotcha), convert with the existing font-trait
  classifier, write markdown + trailing newline.
- Notes whose RTF is missing/unreadable are skipped with a warning on
  stderr; they don't count toward the total.
- Success: `exported N notes to <dir>` on stdout, exit 0.
- Directory creation failure or unwritable file → error on stderr, exit 1.

## Testing

- `CaptureCommandTests`: `export dir` parses, bare `export` errors,
  extra positional errors, `-- export` still captures, `export -- -dir`
  works.
- New `NoteExportTests`: ordering, sanitization, Untitled fallback,
  truncation, collision suffixing.
- Smoke test: fixture `STICKYGRID_DIR` with hand-written notes.json +
  RTF, run the built `sticky export` into a temp dir, check files.
