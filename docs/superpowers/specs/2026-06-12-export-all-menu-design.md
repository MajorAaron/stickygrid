# File → Export All Notes… — GUI twin of `sticky export`

**Date:** 2026-06-12
**Status:** Approved (automated run — decisions made autonomously)

## Problem

`sticky export <dir>` writes the whole store as a folder of markdown
files, but only shell users can reach it. The app itself has single-note
export (⇧⌘E) and nothing for "back up everything" / "fill my Obsidian
vault". The filename planning (`NoteExport`) and the markdown walk
(`MarkdownExport`) already exist — the GUI surface is a thin layer.

## Goals

- File → Export All Notes… (⌥⇧⌘E): pick a folder in an NSOpenPanel,
  every note becomes one `.md` file there, directory created if needed.
- Same filenames as `sticky export` — `NoteExport.entries(for:)` is the
  single source of truth, so the GUI and CLI write identical folders.
- Same content as Copy as Markdown / single-note export: each note's
  live `markdownText()` (notes are all open as panels, so the in-memory
  text is fresher than the RTF on disk).
- The file-writing core is a tested, nonisolated static function on
  WindowManager; the @objc action is panel-and-alert glue.
- Finish with a summary alert: count exported, with a "Show in Finder"
  button (NSWorkspace.activateFileViewerSelecting).

## Non-goals (YAGNI)

- Front-matter/metadata sidecars — same stance as the CLI.
- Incremental/sync export — every run rewrites every file.
- Progress UI — stores are dozens of notes, not thousands; writes are
  synchronous and instant.
- launchd/--watch continuous sync (still backlog).

## Design

New `WindowManager` pieces:

```swift
struct BulkExportResult: Equatable {
    var exported: Int
    var skipped: Int   // empty notes (markdown nil) — nothing to write
}

nonisolated static func exportAllNotes(
    records: [NoteRecord],
    markdown: (UUID) -> String?,
    to directory: URL
) throws -> BulkExportResult
```

- Creates `directory` (withIntermediateDirectories) — throws on failure.
- Iterates `NoteExport.entries(for: records)`; `markdown(id)` nil →
  skipped (the GUI passes `noteMarkdown(id)`, which is nil for empty
  notes — mirrors the CLI skipping unreadable RTF).
- Writes `markdown + "\n"` UTF-8, atomic, overwriting — throws on a
  failed write (surfaced in an error alert by the caller).

`@objc func exportAllNotesAsMarkdown(_:)`: beep if the store is empty;
otherwise NSOpenPanel (choose directories only, canCreateDirectories,
prompt "Export"), call the helper, then the summary or error alert.

Menu: File menu, directly under "Export Note as Markdown…", key `e`
with [.command, .shift, .option].

## Testing

`ExportAllNotesTests` in StickyGridAppTests (@MainActor suite, temp
dirs, fake markdown closure — fully headless):

1. Writes one file per note, NoteExport names, content + trailing
   newline; returns exported count.
2. Empty notes (markdown nil) are skipped and counted.
3. Destination directory is created when missing.
4. Re-export overwrites stale content in place.

Manual GUI verification (menu item, panel, alert) deferred to the user.
