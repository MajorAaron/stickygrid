# Ask Your Notes — AI Q&A across all notes

## What

AI menu → "Ask Your Notes…" (⌥⇧⌘A): type a question, the model reads every
note, and the answer arrives as a **new sticky note** — question as the
title line, answer below, and a Sources section of bare
`stickygrid://open?note=<uuid>` links that are clickable thanks to the
just-shipped link detection. The feature composes three shipped systems:
the AI client (`NoteAI`), markdown note creation (`importedNote(fromMarkdown:)`),
and note deep links.

## Why

Every AI feature so far operates on one note. The grid as a whole is the
user's real knowledge base; this is the first feature that reads it as one
corpus. The answer-as-a-note choice (instead of a results sheet) keeps the
output shareable, exportable, persistent, and linkable like everything else.

## Core: `NoteQA` (new file `Sources/StickyGridCore/NoteQA.swift`)

Pure prompt/corpus assembly — Foundation only, fully headless-testable.

```swift
public enum NoteQA {
    public struct Source: Equatable, Sendable {
        public let id: UUID
        public let title: String   // titleSnippet, "Untitled" fallback
        public let body: String    // markdown, truncated to bodyLimit
    }

    public static let bodyLimit = 4000  // chars per note; keeps corpus bounded

    /// List order (pinned first, then frontmost), nil/empty bodies skipped,
    /// long bodies truncated with a "…" marker line.
    public static func sources(for records: [NoteRecord],
                               body: (UUID) -> String?) -> [Source]

    /// One section per source:
    ///   ## <title>
    ///   Link: stickygrid://open?note=<full lowercased uuid>
    ///
    ///   <body>
    public static func context(for sources: [Source]) -> String

    public static func userMessage(question: String, context: String) -> String

    public static var systemPrompt: String

    /// The new note's markdown: question collapsed to one `# ` title line,
    /// blank line, answer verbatim.
    public static func answerMarkdown(question: String, answer: String) -> String
}
```

`systemPrompt` invariants (pinned by tests):
- answer comes from the provided notes only; admit when they don't answer
- reply is markdown
- Sources section cites the provided `stickygrid://` links as **bare URLs,
  one per line — never `[text](url)`** (only bare textual URLs are clickable
  in notes; pretty links are an unshipped backlog item)

## App glue

- `NoteAI.answer(question:context:)` — one-liner over the existing private
  `complete(system:user:)`.
- `WindowManager.createNote(fromMarkdown:)` — extracted from
  `importNote(from:)` (file read stays behind; the record/upsert/openWindow/
  markTextChanged glue is shared). The answer path reuses it.
- `promptAskNotes()` — app-modal NSAlert (not tied to a panel) with a text
  field, last question remembered in UserDefaults `AILastAskNotesQuestion`,
  mirroring Ask AI's sheet. Preconditions: not already busy, API key set
  (else `promptForAPIKey()`), at least one non-empty note (else beep).
- `performAskNotes(question:sources:)` — `askNotesBusy` flag (this is
  app-level, not per-note `aiBusy`), `NoteAI.answer`, then
  `createNote(fromMarkdown: NoteQA.answerMarkdown(...))`. Errors alert
  app-modally. `validateMenuItem` disables the menu item while busy.
- MainMenuBuilder: "Ask Your Notes…" ⌥⇧⌘A right under "Ask AI…" ⌥⌘A.

Sources are gathered via the `exportAllNotes` pattern: `store.records`
values + the live `noteMarkdown(id)` closure, so panel text (not stale disk
RTF) is what the model reads, and empty notes drop out naturally.

## Tests (red first)

`Tests/StickyGridCoreTests/NoteQATests.swift` — sources ordering/fallback/
skip/truncation, context section format incl. the deep-link line,
userMessage composition, systemPrompt bare-URL + markdown invariants,
answerMarkdown title-line collapse.

App side adds no new testable unit — the glue mirrors already-tested
patterns (importedNote, runAI, exportAllNotes gathering).

## Out of scope

Streaming/progress UI (the per-note spinner has no app-level twin; menu
disable is the busy signal), excluding past answer notes from the corpus,
token-exact budgeting (char cap is enough), AI ⌘F ranking (separate
backlog item).
