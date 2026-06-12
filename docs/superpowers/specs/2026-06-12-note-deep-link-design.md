# Note deep links — `stickygrid://open` + `sticky open`

**Date:** 2026-06-12
**Status:** Approved (automated run — decisions made autonomously)

## Problem

Notes can be created from anywhere (`stickygrid://new`, Services,
clipboard, `sticky`), and read back out (`sticky list/cat`, export),
but nothing can *point at* an existing note. There's no way to jump to
a sticky from another app — no link to paste into an Obsidian page, a
calendar event, or a script. It's also the missing foundation for
note-to-note links (backlog).

## Goals

- `stickygrid://open?note=<query>` raises the matching note's window
  and activates the app. `<query>` is the same matcher as `sticky cat`:
  case-insensitive id-prefix (hyphens ignored) or title substring.
  `id=` accepted as an alias for `note=`.
- `sticky open <query>` resolves the query against the store first
  (good shell errors: "no note matching", ambiguous list — same UX as
  `cat`), then opens `stickygrid://open?note=<full-uuid>`.
- `sticky open --print <query>` prints the URL instead of opening it —
  a durable, unambiguous link to embed in other apps. Validated against
  the store, full UUID in the link.
- Ambiguous query arriving via URL (no shell to print an error): focus
  the best match — first hit in `NoteListing.sorted` order (pinned
  first, then frontmost). A URL should always do *something* useful.
- No match / note's window missing: beep + NSLog, never crash.

## Non-goals (YAGNI)

- Note-to-note links *inside* note text (clickable spans) — next step,
  separate design; this ships the address scheme it will use.
- Scrolling to a text position (`&line=`), opening at a search hit.
- Creating-if-missing (`open-or-new`) semantics.

## Design

Core, new `NoteOpen.swift`:

```swift
public struct OpenRequest: Equatable, Sendable {
    public var query: String
    public static func from(url: URL) -> OpenRequest?   // nil unless host "open" + non-empty note=/id=
    public static func openURL(query: String) -> URL    // inverse, URLComponents encodes
}
```

Core, `NoteListing`:

```swift
public static func bestMatch(_ query: String, in records: [NoteRecord]) -> NoteRecord?
// none → nil, one → it, many → sorted(hits).first
```

Core, `CaptureCommand`: new case `.open(query: String, printOnly: Bool)`,
dispatched when the FIRST arg is exactly `open` (`sticky -- open` still
captures the word, same rule as list/cat/export). Parse mirrors `cat`:
only `--print` is an option, `--` escapes it, other dashed words stay
query text. Empty query → `.missingValue("open")`.

App: `AppDelegate.handleCapture` tries `OpenRequest.from(url:)` before
`CaptureRequest.from(url:)` (hosts are disjoint — `open` vs `new`).
`WindowManager.focusNote(query:)`: `bestMatch` over `store.records`,
`panels[id].makeKeyAndOrderFront` + `NSApp.activate`; beep on miss.

CLI: `.open` loads records, `NoteListing.match` for none/one/many error
copy identical to `cat`, then prints or `/usr/bin/open`s the URL. The
existing open-via-LaunchServices tail of main.swift is extracted into a
shared `launch(url:)` helper used by both `.new` and `.open`.

## Tests (red first)

- `OpenRequestTests` (Core): parses `note=`, `id=` alias, percent
  decoding; rejects host `new`, empty/missing query; `openURL` round-trips
  through `from(url:)`; `CaptureRequest.from` ignores open URLs and
  vice versa.
- `CaptureCommandTests` additions: `open` word dispatch, query joining,
  `--print` anywhere, `--` escape, missing query error, `-- open`
  still captures.
- `NoteListingTests` additions: `bestMatch` none/one/many (pinned wins
  the tie).

Manual GUI verification (deferred to user): build app, `sticky open
<query>` from a terminal raises the right sticky.
