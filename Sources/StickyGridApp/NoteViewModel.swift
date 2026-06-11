import Foundation
import Observation
import StickyGridCore

/// Per-note UI state shared between the SwiftUI content and the window layer.
@Observable
final class NoteViewModel: Identifiable {
    let id: UUID
    var colorID: NoteColor
    var fontName: String
    var fontSize: Double
    var pinned: Bool

    @ObservationIgnored let textController = RichTextController()
    /// RTF loaded from disk before the text view exists; consumed in makeNSView.
    @ObservationIgnored var initialRTF = Data()

    // Wired by WindowManager; SwiftUI never imports the window layer.
    @ObservationIgnored var onNewNote: () -> Void = {}
    @ObservationIgnored var onDelete: () -> Void = {}
    @ObservationIgnored var onTile: () -> Void = {}
    @ObservationIgnored var onAppearanceChanged: () -> Void = {}
    @ObservationIgnored var onTextChanged: () -> Void = {}

    init(record: NoteRecord) {
        id = record.id
        colorID = record.colorID
        fontName = record.fontName
        fontSize = record.fontSize
        pinned = record.pinned
    }
}
