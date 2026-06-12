import Foundation

/// Read-side helpers for the sticky CLI: sorting/formatting `sticky list`
/// lines, resolving `sticky cat` queries, and locating the note store.
/// Pure logic — the CLI glue does the file IO.
public enum NoteListing {

    public enum Match: Equatable, Sendable {
        case none
        case one(NoteRecord)
        case many([NoteRecord])
    }

    /// Pinned first, then frontmost (zOrder 0 is the front window).
    public static func sorted(_ records: [NoteRecord]) -> [NoteRecord] {
        records.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.zOrder < $1.zOrder
        }
    }

    public static func lines(for records: [NoteRecord]) -> [String] {
        sorted(records).map(line)
    }

    private static func line(_ record: NoteRecord) -> String {
        let id8 = record.id.uuidString.lowercased()
            .replacingOccurrences(of: "-", with: "").prefix(8)
        let pin = record.pinned ? "*" : " "
        let title = record.titleSnippet.isEmpty ? "Untitled" : record.titleSnippet
        let padded = title.count < 18
            ? title + String(repeating: " ", count: 18 - title.count)
            : title
        return "\(id8)  \(pin) \(padded) [\(record.colorID.rawValue)]"
    }

    /// Case-insensitive id-prefix (hyphens ignored) or title-substring match.
    public static func match(_ query: String, in records: [NoteRecord]) -> Match {
        let q = query.lowercased()
        let hexQuery = q.replacingOccurrences(of: "-", with: "")
        let hits = records.filter { record in
            let hex = record.id.uuidString.lowercased()
                .replacingOccurrences(of: "-", with: "")
            if !hexQuery.isEmpty, hex.hasPrefix(hexQuery) { return true }
            return record.titleSnippet.lowercased().contains(q)
        }
        switch hits.count {
        case 0: return .none
        case 1: return .one(hits[0])
        default: return .many(hits)
        }
    }

    /// The note a query should act on when there's no shell to report
    /// ambiguity to (the `stickygrid://open` deep link): a unique hit wins,
    /// several hits resolve in list order — pinned first, then frontmost.
    public static func bestMatch(_ query: String, in records: [NoteRecord]) -> NoteRecord? {
        switch match(query, in: records) {
        case .none: return nil
        case .one(let record): return record
        case .many(let hits): return sorted(hits).first
        }
    }

    /// `$STICKYGRID_DIR` wins; otherwise the app's own store location.
    public static func storeDirectory(
        environment: [String: String], home: URL
    ) -> URL {
        if let override = environment["STICKYGRID_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return home
            .appendingPathComponent("Library/Application Support/StickyGrid")
    }
}
