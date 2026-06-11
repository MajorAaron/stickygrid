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

    public init(
        id: UUID = UUID(),
        frame: CGRect,
        colorID: NoteColor = .yellow,
        fontName: String = "Helvetica Neue",
        fontSize: Double = 14,
        pinned: Bool = false,
        zOrder: Int = 0,
        titleSnippet: String = ""
    ) {
        self.id = id
        self.frame = frame
        self.colorID = colorID
        self.fontName = fontName
        self.fontSize = fontSize
        self.pinned = pinned
        self.zOrder = zOrder
        self.titleSnippet = titleSnippet
    }
}
