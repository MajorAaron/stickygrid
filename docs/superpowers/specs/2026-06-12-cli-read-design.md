# sticky list / sticky cat — read notes from the shell

**Date:** 2026-06-12
**Status:** Approved (automated run — decisions made autonomously)

## Problem

Last hour's `sticky` CLI pushes notes *into* StickyGrid from the shell, but
nothing reads them back out. Completing the round-trip makes the CLI a real
cross-app surface: scripts can capture a note, then later find and print it.

## Goals

- `sticky list` — one line per note: short id, title, color, pin marker.
- `sticky cat <query>` — print one note's text to stdout, found by id prefix
  or title substring.
- All decision logic tested in StickyGridCore; the CLI stays glue.
- Read-only: never writes to the store, safe to run while the app is open.

## Non-goals (YAGNI)

- Markdown output from `cat` (run-flattening lives in the app layer today;
  plain text is enough for v1 and list-marker glyphs read fine in a terminal).
- Editing/deleting from the CLI.
- Options on `list`/`cat` (filters, sort flags).

## CLI surface

```
sticky list                 # all notes, frontmost first, pinned first
sticky cat <query...>       # print the matching note's plain text
sticky [options] [words]    # existing capture behavior, unchanged
```

- A subcommand is recognized only when the **first** argument is exactly
  `list` or `cat`. `sticky -- list` still captures a note whose body is
  "list" — the documented escape hatch.
- `cat` joins all following positional words into one query string.
- `cat` with no query is a usage error (exit 64).

## Behavior

**Store location:** `$STICKYGRID_DIR` if set, else
`~/Library/Application Support/StickyGrid`. Resolution is a pure Core
function taking the environment and home directory as parameters.

**list:** decode `notes.json` (`NotesDocument` — already in Core). Sort:
pinned notes first, then `zOrder` ascending (0 = frontmost, matching the
app). Line format:

```
1a2b3c4d  * Groceries          [yellow]
9f8e7d6c    Untitled           [blue]
```

8-char lowercase id prefix, `*` pin column, title (`titleSnippet`, or
`Untitled` when empty — the app's own display rule), color in brackets.
The title column pads with spaces to 18 characters; longer titles simply
push the color right. Missing/empty store → `no notes`, exit 0.

**cat:** match the query case-insensitively against (a) the UUID's hex
prefix (hyphens ignored) and (b) the title as a substring.

- exactly one match → read `<id>.rtf`, print its plain text
  (`NSAttributedString(rtf:)` in the CLI glue — AppKit import lives only in
  StickyCLI), exit 0. Missing RTF for a matched record → empty note, print
  nothing, exit 0.
- zero matches → `sticky: no note matching "<query>"` on stderr, exit 1.
- several matches → stderr lists the candidates using the same listing
  lines, exit 1.

## Architecture

**Core (tested):**

1. `CaptureCommand` gains `.list` and `.cat(query: String)` cases.
   `parse` dispatches on the first argument; `cat` with nothing after it
   throws `.missingValue("cat")`.
2. New `NoteListing` enum (Sources/StickyGridCore/NoteListing.swift):
   - `lines(for: [NoteRecord]) -> [String]` — sort + format, pure.
   - `match(_ query: String, in: [NoteRecord]) -> Match` with
     `enum Match: Equatable { case none, one(NoteRecord), many([NoteRecord]) }`.
   - `storeDirectory(environment: [String: String], home: URL) -> URL`.

**CLI (glue, untested):** main.swift handles the two new command cases —
file IO, RTF decode, printing, exit codes. Usage text gains the
subcommands.

## Testing

- `CaptureCommandTests`: `list` parses, `cat` joins words, bare `cat`
  throws, `-- list` stays a capture, options-first args never dispatch.
- New `NoteListingTests`: sort order (pin beats zOrder), line format and
  padding, Untitled fallback, prefix match (case, hyphens), title substring
  match, ambiguity, env-override vs default directory.
- CLI smoke check by hand: run `sticky list` against a temp
  `STICKYGRID_DIR` with a fixture notes.json — never against the user's
  real store from the automated run.
