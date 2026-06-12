# Markdown Body in Capture

**Date:** 2026-06-12
**Status:** Approved (autonomous scheduled run — design choices recorded below)

## Problem

Every capture path delivers plain text. `stickygrid://new?text=...` and the
`sticky` CLI drop the body into a note verbatim, so markdown arriving from
other apps — a script's output, a snippet piped from the shell, a URL built
by an automation — lands as literal `**asterisks**` and `- dashes`. The
styling machinery already exists: `MarkdownImport` parses markdown into
styled runs and line markers, and `WindowManager.importedNote(fromMarkdown:record:)`
renders it to note RTF (used by file import and drag-and-drop). Capture is
the only inbound path that can't use it.

This closes the shell round-trip symmetrically: `sticky cat -m` already gets
styled notes *out* as markdown; this lets markdown back *in*.

## Approaches considered

- **A (chosen): explicit opt-in flag.** `markdown=1` URL param,
  `-m/--markdown` CLI flag. On arrival the app renders the body through the
  existing import path. Existing automations keep their exact behavior;
  callers state intent.
- **B: auto-detect.** Run `MarkdownImport.detectsMarkdown` on every capture
  and style when it fires. No API change, but plain-text captures containing
  `*` or `- ` lines (shell output, diffs, log excerpts — common CLI piping
  cases) would silently restyle. Rejected: capture must be predictable.
- **C: render in the CLI.** Not viable — the URL scheme carries text, and
  the CLI has no access to the destination note's font/ink/color context.

## Design

### Core: CaptureRequest (`NoteCapture.swift`)

- New field `public var markdown: Bool` (default `false` in the init).
- `from(url:)` reads a `markdown` query param: values `1` or `true`
  (case-insensitive) set it; anything else (or absence) leaves it false.
- `captureURL(body:title:color:)` gains a `markdown: Bool` parameter and
  appends `markdown=1` when true, omits it when false — staying the exact
  inverse of `from(url:)`.
- `from(plainText:)` is unchanged (clipboard/Services stay plain).

### Core: CaptureCommand (`CaptureCommand.swift`)

- `.new` gains a `markdown: Bool` associated value:
  `.new(body:title:color:printOnly:markdown:)`.
- Capture-mode parsing accepts `-m` / `--markdown` (mirrors the same flag on
  `cat`: markdown in, markdown out). After `--` it is a body word, like
  every other option.

### App: WindowManager

- `createNote(from:)` branches on `request.markdown`: when set and the text
  is non-empty, render via the existing `importedNote(fromMarkdown:record:)`
  scratch-editor path instead of the plain `rtf(from:record:)`, and take the
  title snippet from the *rendered* text (so `# Heading` becomes `Heading`
  in the listing, matching file import).
- To keep that decision headlessly testable, extract a static helper
  `captureContent(for request: CaptureRequest, record: NoteRecord)
  -> (rtf: Data?, titleSnippet: String)` that picks the path; `createNote`
  calls it. Plain requests return `rtf(from:record:)` output and
  `request.titleSnippet` exactly as today; empty text returns nil RTF.
- An explicit `title=` param joins the body before parsing, so with
  `markdown=1` the title line goes through the markdown parser too. A plain
  title parses to plain runs; this is documented, not special-cased.
  `hasExplicitTitle` and auto-title/auto-color behavior are untouched.

### CLI: main.swift

- Pass the parsed flag to `captureURL`. Usage text gains the capture-mode
  meaning of `-m` and a piped example
  (`sticky cat -m release | sticky -m -t "Copy"` round-trip).

### Out of scope

Markdown in the Services/clipboard capture paths (no place to express the
flag), headings beyond the existing bold-flatten behavior of
`MarkdownImport`, and a `markdown=0` override.

## Testing

TDD, red first.

- **CaptureRequestTests:** `markdown=1` and `markdown=TRUE` parse true;
  absent, `0`, and garbage parse false.
- **CaptureURLTests:** `captureURL(... markdown: true)` emits `markdown=1`
  and round-trips through `from(url:)`; `markdown: false` omits the param.
- **CaptureCommandTests:** `-m` and `--markdown` set the flag on `.new`;
  `sticky -- -m` keeps it as a body word; existing `.new` assertions gain
  the new associated value.
- **App (MarkdownCaptureTests):** `captureContent` with a markdown request
  containing `**bold**` yields RTF whose attributed form has a bold run and
  a snippet without asterisks; the same body without the flag yields literal
  asterisks; `# Title` body yields snippet `Title`; empty text yields nil
  RTF. Suites need `@MainActor` (module default isolation).
