import Foundation

/// Filename planning for `sticky export`: one collision-safe `.md` name per
/// note, derived from its title. Pure logic — the CLI does the file IO.
public enum NoteExport {

    public struct Entry: Equatable, Sendable {
        public let id: UUID
        public let filename: String
    }

    /// Notes in `list` order (pinned first, then frontmost) so collision
    /// suffixes land deterministically: the first note with a title keeps
    /// the clean name, later duplicates get `-<id8>`.
    public static func entries(for records: [NoteRecord]) -> [Entry] {
        var taken: Set<String> = []
        return NoteListing.sorted(records).map { record in
            var name = sanitizedBase(record.titleSnippet)
            // Collisions are resolved case-insensitively — the default
            // APFS volume won't hold both Groceries.md and groceries.md.
            if !taken.insert(name.lowercased()).inserted {
                let id8 = record.id.uuidString.lowercased()
                    .replacingOccurrences(of: "-", with: "").prefix(8)
                name += "-\(id8)"
                taken.insert(name.lowercased())
            }
            return Entry(id: record.id, filename: name + ".md")
        }
    }

    private static func sanitizedBase(_ title: String) -> String {
        let dashed = title.map { ch -> Character in
            if ch == "/" || ch == ":" { return "-" }
            return ch
        }
        let collapsed = String(dashed)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // Leading dots would make the export a hidden file.
        var base = String(collapsed.drop(while: { $0 == "." }))
        if base.count > 60 { base = String(base.prefix(60)) }
        base = base.trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "Untitled" : base
    }
}
