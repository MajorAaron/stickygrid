import Foundation

/// Backlinks — which notes link TO a given note. A pure LinkDetection scan
/// over the live grid, no AI involved: the reverse direction of the edges
/// Copy Link to Note and Find Related Notes write forward.
public enum NoteBacklinks {

    /// IDs of the notes `text` links to: every stickygrid://open URL found
    /// by LinkDetection, its query resolved with the same matcher deep
    /// links use (NoteListing.bestMatch) — so hand-written id-prefix and
    /// title-substring links count, not just the full-UUID links the app
    /// generates, and a backlink shows up exactly where clicking the link
    /// would land.
    public static func linkedIDs(in text: String, records: [NoteRecord]) -> Set<UUID> {
        Set(LinkDetection.matches(in: text).compactMap { match in
            OpenRequest.from(url: match.url).flatMap {
                NoteListing.bestMatch($0.query, in: records)?.id
            }
        })
    }

    /// The notes whose text links to `target`, in list order (pinned
    /// first, then frontmost). The target itself never counts — a
    /// self-link is not a backlink. Bodies come from the caller (live
    /// editor text, untruncated — unlike the QA corpus, a link past any
    /// budget cutoff must still count); nil bodies are skipped.
    public static func records(
        linkingTo target: UUID, in records: [NoteRecord], body: (UUID) -> String?
    ) -> [NoteRecord] {
        NoteListing.sorted(records).filter { record in
            guard record.id != target, let text = body(record.id) else { return false }
            return linkedIDs(in: text, records: records).contains(target)
        }
    }
}
