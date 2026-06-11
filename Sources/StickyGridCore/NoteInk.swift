import Foundation

/// Per-note text color. `auto` follows the background's tuned foreground;
/// the rest are bold marker inks that stay fixed on any background.
public enum NoteInk: String, Codable, CaseIterable, Sendable, Equatable {
    case auto, black, red, blue, green, violet, orange

    /// The color to draw the note's text with on the given background.
    public func resolved(on background: NoteColor) -> NoteColor.RGB {
        switch self {
        case .auto:   background.foreground
        case .black:  NoteColor.RGB(red: 0.07, green: 0.07, blue: 0.07)
        case .red:    NoteColor.RGB(red: 0.75, green: 0.22, blue: 0.17)
        case .blue:   NoteColor.RGB(red: 0.12, green: 0.37, blue: 0.75)
        case .green:  NoteColor.RGB(red: 0.12, green: 0.49, blue: 0.20)
        case .violet: NoteColor.RGB(red: 0.48, green: 0.18, blue: 0.75)
        case .orange: NoteColor.RGB(red: 0.78, green: 0.36, blue: 0.07)
        }
    }
}
