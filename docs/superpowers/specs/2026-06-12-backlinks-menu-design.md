# Backlinks — "Linked Here" section in the Notes menu

## What

The Notes menu (the navigation menu rebuilt on every open) grows a
**Linked Here** section above the all-notes list: the notes whose text
links *to* the front note, one item each, choosing one focuses it. No AI,
no API key — a pure `LinkDetection` scan over the live grid, recomputed
every time the menu opens, so it can never go stale the way an appended
section would.

## Why

Find Related Notes writes forward edges (a Related section of
`stickygrid://open` links). Backlinks are the reverse direction — "what
points here?" — and they complete the wiki loop: Copy Link to Note and
Find Related Notes create edges, clickable links traverse them forward,
Linked Here traverses them backward. Item one of the idea backlog.

## Core: `NoteBacklinks` (new file `Sources/StickyGridCore/NoteBacklinks.swift`)

Foundation only, fully headless.

```swift
public enum NoteBacklinks {
    /// IDs of the notes `text` links to: every stickygrid://open URL found
    /// by LinkDetection, its query resolved with the same matcher deep
    /// links use (NoteListing.bestMatch) — so hand-written id-prefix and
    /// title-substring links count, not just the full-UUID links the app
    /// generates.
    public static func linkedIDs(in text: String, records: [NoteRecord]) -> Set<UUID>

    /// The notes whose text links to `target`, in list order (pinned
    /// first, then frontmost). The target itself never counts (self-links
    /// are not backlinks); notes whose body closure returns nil are
    /// skipped.
    public static func records(
        linkingTo target: UUID, in records: [NoteRecord], body: (UUID) -> String?
    ) -> [NoteRecord]
}
```

Decisions:

- **Resolution mirrors deep-link semantics.** A title-substring query like
  `note=plan` resolves to the single note `bestMatch` would raise, so a
  backlink shows up exactly where clicking the link would land. No
  one-query-many-backlinks fan-out.
- **Full text, not the QA corpus.** `NoteQA.sources` truncates bodies at
  4000 chars for the request budget; a link past the cutoff would silently
  vanish. Backlinks scan the untruncated text.
- **Set-based linkedIDs.** A note linking twice is one backlink; order of
  backlinks comes from `NoteListing.sorted`, not link positions.

## App glue (WindowManager)

`menuNeedsUpdate(_:)` prepends the section before the existing all-notes
list:

- Front note via `noteID(of: NSApp.keyWindow)` — no focused note, no
  section. Bodies come from live editors (`textController.plainText()`),
  like ⌘F search, so unsaved text counts.
- Non-empty result renders: disabled "Linked Here" header, one
  `focusNote(_:)` item per backlink at `indentationLevel` 1 (title
  fallback "Untitled"), then a separator. Zero backlinks → no section at
  all; the menu stays exactly as it was.

## Tests

- Core `NoteBacklinksTests` (red first): linkedIDs finds open-links in
  prose and resolves full UUIDs, id-prefixes, and title queries; ignores
  `https://` and `stickygrid://new` URLs; unknown UUIDs resolve to
  nothing. records(linkingTo:) keeps list order, excludes the
  self-linking target, skips nil bodies, dedupes double-linkers.
- Menu glue is mechanical AppKit; manual GUI verification deferred to the
  user, as usual.

## Out of scope (backlog)

`sticky backlinks <query>` CLI twin; a floating backlinks panel with
snippets; re-run Related replacing the stale section.
