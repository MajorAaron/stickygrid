import Foundation

/// Versioned wrapper around the persisted note list (`notes.json`).
public struct NotesDocument: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var notes: [NoteRecord]

    public init(version: Int = NotesDocument.currentVersion, notes: [NoteRecord] = []) {
        self.version = version
        self.notes = notes
    }

    public static func decode(from data: Data) throws -> NotesDocument {
        try JSONDecoder().decode(NotesDocument.self, from: data)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
