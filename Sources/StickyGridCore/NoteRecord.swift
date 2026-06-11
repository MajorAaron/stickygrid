import CoreGraphics
import Foundation

/// Persisted metadata for one sticky note. The note's rich text lives in a
/// sibling `<id>.rtf` file, not in this record.
public struct NoteRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var frame: CGRect
    public var colorID: NoteColor
    public var fontName: String
    public var fontSize: Double
    public var pinned: Bool
    public var zOrder: Int
    public var titleSnippet: String
    public var ink: NoteInk

    public init(
        id: UUID = UUID(),
        frame: CGRect,
        colorID: NoteColor = .yellow,
        fontName: String = "Helvetica Neue",
        fontSize: Double = 14,
        pinned: Bool = false,
        zOrder: Int = 0,
        titleSnippet: String = "",
        ink: NoteInk = .auto
    ) {
        self.id = id
        self.frame = frame
        self.colorID = colorID
        self.fontName = fontName
        self.fontSize = fontSize
        self.pinned = pinned
        self.zOrder = zOrder
        self.titleSnippet = titleSnippet
        self.ink = ink
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frame = try container.decode(CGRect.self, forKey: .frame)
        colorID = try container.decode(NoteColor.self, forKey: .colorID)
        fontName = try container.decode(String.self, forKey: .fontName)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        pinned = try container.decode(Bool.self, forKey: .pinned)
        zOrder = try container.decode(Int.self, forKey: .zOrder)
        titleSnippet = try container.decode(String.self, forKey: .titleSnippet)
        // Added after 1.0 — older documents have no ink field.
        ink = try container.decodeIfPresent(NoteInk.self, forKey: .ink) ?? .auto
    }
}
