# Shell capture: the `sticky` command-line tool

2026-06-12

## Problem

Every capture path so far needs a GUI gesture: the Quick Capture palette,
the Services menu, ⇧⌘N, or hand-writing a `stickygrid://new` URL. Power
users live in the terminal and in launchers (Raycast, Alfred, Shortcuts'
"Run Shell Script") — there is no scriptable way to make a note. The URL
scheme already does all the work; what's missing is a tiny tool that
builds the URL correctly (percent-encoding is fiddly to get right in
shell) and opens it.

## Shape

A second SwiftPM executable, `sticky`, that turns arguments and stdin into
a `stickygrid://new` URL and hands it to `/usr/bin/open`:

```
sticky Buy milk                         # words join into the body
echo "milk\neggs" | sticky              # no args → body from stdin
sticky --title Groceries --color pink "milk and eggs"
git log --oneline -5 | sticky -t "Release notes"
sticky --print "hi there"               # print the URL, don't open it
```

## Design

Two pure, tested pieces in `StickyGridCore`, one thin untested `main.swift`.

### 1. URL builder — the inverse of `CaptureRequest.from(url:)`

```swift
extension CaptureRequest {
    public static func captureURL(body: String?, title: String?, color: NoteColor?) -> URL
}
```

- Emits `stickygrid://new` with `text=`, `title=`, `color=` query items,
  omitting nil/empty params; bare `stickygrid://new` when everything is nil.
- Round-trip invariant (the real test): for any inputs,
  `CaptureRequest.from(url: captureURL(...))` reproduces the joined text,
  the color, and `hasExplicitTitle`. URLComponents does the
  percent-encoding (newlines, `&`, unicode).

### 2. Argument parser — `CaptureCommand` in Core

```swift
public enum CaptureCommand: Equatable, Sendable {
    case help
    case new(body: String?, title: String?, color: NoteColor?, printOnly: Bool)
    public static func parse(_ args: [String]) throws(ParseError) -> CaptureCommand
}
```

- Positional words join with a single space into the body; no positionals
  → body nil (main decides whether stdin fills it).
- `--title v` / `-t v`, `--color v` / `-c v`, `--print`, `--help` / `-h`.
- `--` ends option parsing so a body can start with a dash.
- Errors (`ParseError: Error, Equatable`): `unknownOption`,
  `missingValue`, `unknownColor` — color is validated against
  `NoteColor` (case-insensitive, "grey" → gray like the AI parser).
- `--help` anywhere wins over everything else.

### 3. `StickyCLI` executable target — thin glue

- Foundation only (no AppKit): launches `/usr/bin/open <url>` via
  `Process` and waits, so it works from any context and the app gets
  routed through LaunchServices like every other capture.
- body nil and stdin is not a TTY → read stdin (trailing newline trimmed).
- body nil, no title, nothing piped → print usage to stderr, exit 64
  (EX_USAGE) — a bare `sticky` at a prompt should explain itself, not
  silently open an empty note.
- `--print` prints the URL to stdout and exits 0 without opening.
- `open` failing → message on stderr, its exit code propagated.

### Packaging

- `Package.swift`: product `.executable(name: "sticky", targets:
  ["StickyCLI"])`, target depends on `StickyGridCore` only.
- Install is `swift build -c release` + copy
  `.build/release/sticky` somewhere on `$PATH`; README documents it in
  the capture section.

## Non-goals

- No reading notes back out, no list/search subcommands — capture only.
- No daemon/IPC; the URL scheme stays the single doorway into the app.
- The GUI app must already be built/registered for `open` to route the
  URL; the CLI does not try to locate or launch the .app itself.

## Tests

`CaptureURLTests` (builder round-trips, encoding edges, bare URL) and
`CaptureCommandTests` (joins, flags, `--`, stdin sentinel, every error)
in StickyGridCoreTests. `main.swift` stays under ~60 lines of glue.
