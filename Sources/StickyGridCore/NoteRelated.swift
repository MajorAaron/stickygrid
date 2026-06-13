import Foundation

/// Prompt assembly and reply parsing for Find Related Notes — the AI
/// feature that links one note to the rest of the grid. Pure string work;
/// the app glue gathers the corpus (every note but the current one, via
/// `NoteQA`) and appends the Related section.
public enum NoteRelated {

    /// Most links the model may cite — and a hard cap on the parse, so a
    /// rambling reply can't flood the note.
    public static let maxLinks = 5

    public static var systemPrompt: String {
        """
        You find the sticky notes related to the note the owner is reading. \
        The user message gives that note first, then every other note — each \
        with its title, its stickygrid:// link, and its text.

        Reply with ONLY the stickygrid:// links of the notes genuinely \
        related to the current note: one bare URL per line, most related \
        first, at most \(maxLinks) lines. Never wrap links in [text](url) \
        syntax — only bare URLs are clickable in notes. Never invent links.

        If nothing is genuinely related, reply with exactly: NONE
        """
    }

    /// The current note (title + markdown body, truncated like the QA
    /// corpus) above the context of the other notes.
    public static func userMessage(
        title: String, body: String, context: String
    ) -> String {
        """
        Current note:

        ## \(title)

        \(NoteQA.truncated(body))

        Other notes:

        \(context)
        """
    }

    /// Note IDs cited in the reply, in reply order: every stickygrid://open
    /// URL (found with the same detector notes use, so prose and markdown
    /// wrapping don't matter) whose note query is a UUID present in `valid`.
    /// Deduped, capped at `maxLinks` — hallucinated links cannot survive.
    public static func ids(fromReply reply: String, valid: Set<UUID>) -> [UUID] {
        var seen = Set<UUID>()
        var ids: [UUID] = []
        for match in LinkDetection.matches(in: reply) {
            guard ids.count < maxLinks,
                  let request = OpenRequest.from(url: match.url),
                  let id = UUID(uuidString: request.query),
                  valid.contains(id), seen.insert(id).inserted
            else { continue }
            ids.append(id)
        }
        return ids
    }

    /// UTF-16 ranges of every rendered Related section in note plain text —
    /// `relatedMarkdown`'s inverse across the insertMarkdown render
    /// boundary, recomputed live so a re-run can replace instead of stack.
    /// A section is a line reading exactly `Related:` plus one or more
    /// bullet lines carrying a stickygrid deep link; a `Related:` line over
    /// prose is the user's text and never matches. Each range also claims
    /// the newline run just before the section (or, when the section starts
    /// the note, just after) but stops at the last bullet's content, so
    /// removal neither stacks blank lines nor swallows the gap in front of
    /// any text below.
    public static func sectionRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        let bullet = MarkdownTyping.LineMarker.bullet.literal
        var lines: [(content: NSRange, full: NSRange)] = []
        var index = 0
        while index < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                            for: NSRange(location: index, length: 0))
            lines.append((NSRange(location: start, length: contentsEnd - start),
                          NSRange(location: start, length: end - start)))
            index = end
        }

        func isLinkBullet(_ content: NSRange) -> Bool {
            let line = ns.substring(with: content)
            return line.hasPrefix(bullet) && line.contains("stickygrid://open?note=")
        }

        var ranges: [NSRange] = []
        var i = 0
        while i < lines.count {
            let header = lines[i]
            let title = ns.substring(with: header.content)
                .trimmingCharacters(in: .whitespaces)
            guard title == "Related:" else { i += 1; continue }
            var last = i
            while last + 1 < lines.count, isLinkBullet(lines[last + 1].content) {
                last += 1
            }
            guard last > i else { i += 1; continue }

            var start = header.full.location
            var end = NSMaxRange(lines[last].content)
            if start > 0 {
                while start > 0, ns.character(at: start - 1) == 0x0A { start -= 1 }
            } else {
                while end < ns.length, ns.character(at: end) == 0x0A { end += 1 }
            }
            ranges.append(NSRange(location: start, length: end - start))
            i = last + 1
        }
        return ranges
    }

    /// The markdown appended to the note, or nil when there is nothing to
    /// append. Title first — this section is for rereading, so scannability
    /// beats the bare-URL style of Ask Your Notes sources; only the URL run
    /// becomes clickable.
    public static func relatedMarkdown(for sources: [NoteQA.Source]) -> String? {
        guard !sources.isEmpty else { return nil }
        let lines = sources.map { source in
            "- \(source.title) — stickygrid://open?note=\(source.id.uuidString.lowercased())"
        }
        return "Related:\n" + lines.joined(separator: "\n")
    }
}
