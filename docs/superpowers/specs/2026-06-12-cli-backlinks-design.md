# CLI Backlinks — `sticky backlinks <query>`

## What

A fifth read-only `sticky` subcommand: `sticky backlinks <query>` resolves
the query exactly like `cat`/`open` (none/many errors with the listing),
then prints the notes whose text links *to* that note, one `sticky list`
formatted line each. The shell twin of the Notes menu's Linked Here
section, item one of the idea backlog.

## Why

Linked Here answers "what points here?" only inside the GUI. Scripts and
shell workflows (the same ones that use `list`/`cat`/`export`) get the
reverse-link graph too — e.g. check what would dangle before deleting a
note, or feed a graph tool. Pure reuse: `NoteBacklinks.records` is already
tested; the new surface is one parse case and glue.

## Parse: `CaptureCommand.backlinks(query: String)`

- Dispatched only when the FIRST arg is exactly `backlinks` (same rule as
  list/cat/open/export); `sticky -- backlinks` still captures the word.
- Same scanning rule as cat/open: no options at all here, but a leading-
  scan `--` still escapes, so dashed words can be query text either way.
  Remaining words join with spaces into the query.
- No words → `ParseError.missingValue("backlinks")`.

## CLI glue (main.swift)

- Resolve via `NoteListing.match(query:)` — `.none` and `.many` fail
  exactly like cat (exit 1, listing on many).
- `.one(record)`: bodies for the scan come from disk RTF plain text,
  `loadText(id:)?.string` — the CLI's store-on-disk view, untruncated.
- Output: `NoteListing.lines(for:)` of the backlinking records — same
  format as `sticky list`, so ids pipe straight into `sticky cat`/`open`.
- Zero backlinks: print `no notes link to "<title>"` (Untitled fallback)
  and exit 0 — an empty result is an answer, not an error.
- Usage text gains the subcommand and an example.

## Tests

- Core `CaptureCommandTests` (red first): backlinks joins words into one
  query; `--` escape; dashed query words survive; no query throws
  missingValue("backlinks"); `-- backlinks` still captures.
- Backlink semantics already pinned by `NoteBacklinksTests` — not
  re-tested.
- Smoke test against a fixture `STICKYGRID_DIR` (hand-written notes.json +
  RTF, as before): hit, zero-backlinks, and ambiguous-query paths.

## Out of scope (backlog)

Floating backlinks panel with snippets; `--print`-style link output;
counting forward links (`sticky links <query>`).
