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
    var ink: NoteInk
    /// True while an AI transform of this note is in flight.
    var aiBusy = false

    @ObservationIgnored let textController = RichTextController()
    /// RTF loaded from disk before the text view exists; consumed in makeNSView.
    @ObservationIgnored var initialRTF = Data()

    // Wired by WindowManager; SwiftUI never imports the window layer.
    @ObservationIgnored var onNewNote: () -> Void = {}
    @ObservationIgnored var onDelete: () -> Void = {}
    @ObservationIgnored var onTile: () -> Void = {}
    @ObservationIgnored var onAppearanceChanged: () -> Void = {}
    @ObservationIgnored var onTextChanged: () -> Void = {}
    @ObservationIgnored var onAIAction: (NoteAIAction) -> Void = { _ in }
    @ObservationIgnored var onAskAI: () -> Void = {}
    @ObservationIgnored var onSuggestColor: () -> Void = {}
    @ObservationIgnored var onSuggestTitle: () -> Void = {}
    @ObservationIgnored var onFindRelated: () -> Void = {}
    @ObservationIgnored var onShare: () -> Void = {}
    @ObservationIgnored var onImportFiles: ([URL]) -> Void = { _ in }
    /// Fires with the open query when a stickygrid://open link is clicked.
    @ObservationIgnored var onOpenNoteLink: (String) -> Void = { _ in }

    init(record: NoteRecord) {
        id = record.id
        colorID = record.colorID
        fontName = record.fontName
        fontSize = record.fontSize
        pinned = record.pinned
        ink = record.ink
    }
}
