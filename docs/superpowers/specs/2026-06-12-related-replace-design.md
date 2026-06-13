# Find Related Notes — re-run replaces the Related section

**Date:** 2026-06-12
**Status:** Approved (autonomous scheduled run — design choices noted below)

## Problem

Find Related Notes appends a `Related:` section of deep links to the note.
Running it again appends a *second* section under the first, and a third
after that. The grid changes over time — re-running should refresh the
section, not stack duplicates.

## Decision

Re-running Find Related Notes **removes every existing Related section**
from the note, then appends the fresh one. Removing all (not just the
last) means notes that already stacked duplicates self-heal on the next
run.

Detection is recomputed from the live note text at replace time — the
same philosophy as `restyleLinks` and the backlinks menu. No stored
ranges or metadata to go stale.

## What counts as a Related section (rendered text)

`relatedMarkdown` emits markdown; by the time it sits in a note it has
been rendered by `insertMarkdown`. The rendered shape, in plain text:

```
Related:
•\t<title> — stickygrid://open?note=<uuid>
•\t<title> — stickygrid://open?note=<uuid>
```

A section is:

- a line whose whitespace-trimmed content is exactly `Related:`,
- followed immediately by **one or more** consecutive lines that start
  with the rendered bullet literal (`LineMarker.bullet.literal`, i.e.
  `\u{2022}\t`) **and** contain `stickygrid://open?note=`.

The section ends at the first line that breaks the shape. A `Related:`
line with no qualifying bullet under it is **not** a section — a user
who typed `Related:` over prose keeps their text. A bullet without a
deep link ends the section and survives.

The reported range also consumes the run of blank lines (and the
newline) immediately *before* `Related:`, so delete-then-append doesn't
grow a ladder of blank separators, and it includes the section's
trailing newline when one exists so no empty line is left behind
mid-note.

## Components

### Core — `NoteRelated.sectionRanges(in:) -> [NSRange]`

Pure string scan over plain note text, UTF-16 NSRanges (same convention
as `LinkDetection.matches`). Returns every section in text order; empty
array when there is none. Lives next to `relatedMarkdown` — the two are
inverses across the render boundary.

### App — `RichTextController.replaceRelated(_ markdown: String)`

1. `NoteRelated.sectionRanges(in: plainText())`, deleted in **reverse**
   order so earlier ranges stay valid; each deletion goes through
   `shouldChangeText`/`didChangeText` so it is undoable and restyles
   fire.
2. `appendMarkdown(markdown)` — the existing tested append path; links
   clickable immediately.

Both edits land in the same runloop turn, so the undo manager groups
them into one undo.

`WindowManager.performFindRelated` swaps `appendMarkdown(markdown)` for
`replaceRelated(markdown)`. No other glue changes; the "no related
notes found" alert path does NOT remove an existing section (an old
answer beats no answer).

## Rejected alternatives

- **Replace only the last section** — leaves historical stacked
  duplicates in place forever.
- **Track the appended range as note metadata** — stale the moment the
  user edits; recompute-from-text is the established pattern.

## Tests

Core (`RelatedNotesTests` additions): no section → `[]`; section at
end / at start / mid-note with following text preserved; preceding
blank-line gap consumed; two stacked sections both found; `Related:`
over prose not matched; non-link bullet ends the section.

App (`RelatedAppendTests` additions): replaceRelated on a note with an
old section yields exactly one fresh section; on a section-free note it
behaves like append; stacked duplicates collapse to one; user text
after the section survives.
