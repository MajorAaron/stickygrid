# Find Related Notes — AI links from one note to the rest of the grid

## What

Sparkles menu → "Find Related Notes" (and AI menu → "Find Related Notes"):
the model reads the front note plus every *other* non-empty note and picks
up to 5 that are genuinely related. A **Related** section is appended to the
front note — one bullet per related note, title plus a bare
`stickygrid://open?note=<uuid>` link, clickable thanks to shipped link
detection. The inverse of Ask Your Notes: instead of the grid answering a
question with a new note, an existing note grows edges into the grid.

## Why

Ask Your Notes made the grid a corpus; deep links made notes addressable;
clickable links made addresses usable. Related Notes composes all three into
the first *navigational* AI feature — the grid starts behaving like a tiny
personal wiki whose backlink sections write themselves.

## Core: `NoteRelated` (new file `Sources/StickyGridCore/NoteRelated.swift`)

Pure prompt assembly + reply parsing — Foundation only, fully headless.

```swift
public enum NoteRelated {
    public static let maxLinks = 5

    public static var systemPrompt: String

    /// Current note (title + markdown body, body truncated with
    /// NoteQA.truncated) above the corpus context (NoteQA.context of the
    /// OTHER notes — the caller excludes the current note).
    public static func userMessage(title: String, body: String,
                                   context: String) -> String

    /// Note IDs cited in the model's reply, in reply order: every
    /// stickygrid://open URL found by LinkDetection, parsed by OpenRequest,
    /// whose query is a UUID in `valid`. Deduped, capped at maxLinks.
    /// Robust to prose, markdown wrapping, and invented links (dropped).
    public static func ids(fromReply reply: String,
                           valid: Set<UUID>) -> [UUID]

    /// The appended markdown, or nil when sources is empty:
    ///   Related:
    ///   - <title> — stickygrid://open?note=<uuid>
    public static func relatedMarkdown(for sources: [NoteQA.Source]) -> String?
}
```

`systemPrompt` invariants (pinned by tests):
- reply is ONLY the `stickygrid://open` links of related notes, one per
  line, most related first, at most `maxLinks`
- bare URLs — never `[text](url)` (only bare URLs are clickable)
- reply exactly `NONE` when nothing is genuinely related; never invent links

`ids(fromReply:valid:)` is the trust boundary: the model's reply is parsed
with the same `LinkDetection` regex notes use, then validated against the
IDs that were actually in the corpus — hallucinated or malformed links
cannot survive into the note.

## App glue

- `NoteAI.relatedNotes(title:body:context:)` — one `complete` round trip
  over `NoteRelated` prompts (same shape as `answer(question:context:)`).
- `RichTextController.appendMarkdown(_:)` — caret to end-of-note, blank-line
  separator when the note has text, then the existing `insertMarkdown`
  paste path renders it (real bullets, undo in one step, `didChangeText`
  fires `restyleLinks` so the links are clickable immediately).
- `WindowManager.relatedSources(records:excluding:body:)` — nonisolated
  static, the tested corpus rule: `NoteQA.sources` of every note *except*
  the current one.
- `WindowManager.findRelatedNotes(on:)` — mirrors `performSuggestTitle`:
  per-note `aiBusy` guard, beep on empty note or empty corpus, key prompt,
  then append on success; informational alert when the reply is `NONE`
  (silence would read as a hang).
- Surfaces: sparkles menu button + AI menu item "Find Related Notes",
  `NoteViewModel.onFindRelated`, no key equivalent (menu real estate is
  getting tight; revisit if it earns one).

## Format choice

`- Title — link` (title first) rather than the bare-URL-only style of Ask
Your Notes sources: this section lives inside a note the user rereads, so
scannability wins. Only the URL run is clickable; the title is plain text.

## Tests

Core (`RelatedNotesTests`): ids extraction order/dedup/cap, unknown and
malformed links dropped, `NONE`/prose → empty, markdown-wrapped link still
extracted; relatedMarkdown format + nil-on-empty; userMessage embeds
title/body/context + truncates long bodies; systemPrompt contract strings.

App (`RelatedAppendTests`, @MainActor): appendMarkdown on empty vs non-empty
note (separator, bullets render, original text intact), `.link` attribute
present on the URL run after append, one undo restores the pre-append text
(UndoHost pattern); `relatedSources` excludes the current note and skips
empty bodies.

Manual GUI verification (menu items, end-to-end with a live key) deferred
to the user, as usual.
