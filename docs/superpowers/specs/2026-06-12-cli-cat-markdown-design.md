# `sticky cat --markdown` — styled notes out of the shell

## Problem

`sticky cat` prints a note's plain text, so styling (bold, lists,
checkboxes, quotes, the auto-header title) is lost the moment a note
leaves the app through the shell. The app already knows how to serialize
a note to markdown (⌥⌘C / ⇧⌘E), but that flattening lives in the app
layer — `StickyTextView+Export.swift` walks `NSTextStorage` with
`NSFontManager` and hands styled runs to `MarkdownExport` in Core. The
CLI can't reach it.

Completing this closes the shell round-trip: markdown can be captured in
(`cat notes.md | sticky`) and now read back out
(`sticky cat -m release | pbcopy`), which makes every other app that
speaks markdown a StickyGrid integration point.

## Design

### Core: shared run-flattening on `MarkdownExport`

`NSAttributedString` is Foundation, so the paragraph walk moves into
Core; only font-trait *classification* is AppKit knowledge, and it stays
in the callers as an injected closure:

```swift
public struct Style: Equatable, Sendable {   // nested in MarkdownExport
    public var bold, italic, strikethrough, code: Bool
}

public static func runs(
    of text: NSAttributedString,
    classify: ([NSAttributedString.Key: Any]) -> Style
) -> [[Run]]

public static func markdown(
    of text: NSAttributedString,
    classify: ([NSAttributedString.Key: Any]) -> Style
) -> String   // = markdown(paragraphs: runs(of:classify:))
```

`runs(of:classify:)` reproduces the app's walk exactly: paragraph split
via `getParagraphStart`, attribute enumeration per paragraph, and the
first-paragraph rule that bold is the auto-header style, not user
emphasis, so it is dropped (the line exports as `# `).

Core stays Foundation-only. Tests drive `classify` with a custom
attribute key — no fonts, no AppKit, fully headless.

### App: refactor onto the shared walker

`StickyTextView.markdownText()` becomes
`MarkdownExport.markdown(of: storage, classify: fontClassifier)` where
the classifier keeps the existing `NSFontManager` traits +
`codeFontName` ("Menlo") prefix check. Behavior is pinned by
`MarkdownExportEndToEndTests`, which must pass unchanged.

### CLI: `-m` / `--markdown` on cat

`CaptureCommand.cat` gains a flag: `.cat(query: String, markdown: Bool)`.
Parse rules after the leading `cat`:

- `-m` / `--markdown` anywhere sets the flag.
- `--` stops flag scanning; everything after is query words (so a note
  titled "-m" stays reachable: `sticky cat -- -m`).
- Other dashed words stay query text, as today — cat has never had
  option errors and titles may contain dashes.
- Empty query after flag removal is still `missingValue("cat")`.

`main.swift` glue: on `.cat(_, markdown: true)`, decode the RTF with the
document-reading initializer (the `init?(rtf:)` headless gotcha) and
print `MarkdownExport.markdown(of:classify:)` using an `NSFont`
classifier mirroring the app's (symbolic traits + "Menlo" prefix). The
classifier is ~8 lines of untested glue, consistent with the rest of
main.swift; the walk and serialization it feeds are Core-tested.

## Tested units

- `MarkdownExport.runs(of:classify:)` / `markdown(of:classify:)` —
  paragraph splitting, classify injection, first-line bold drop,
  marker-literal lines surviving into `- ` / `1. ` / `- [ ] ` / `> `
  prefixes (Core, fake attribute key).
- `CaptureCommand.parse` — `-m`/`--markdown` before/after query words,
  `cat -- -m`, default false, empty-query error (Core).
- App end-to-end export tests pass unchanged after the refactor.

## Out of scope

- `sticky list --markdown` (a listing is not a document).
- Headings/inline-style fidelity beyond what `MarkdownExport` already
  emits.
- Writing notes from the CLI beyond the existing capture path.
