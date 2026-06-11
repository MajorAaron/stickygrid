import Foundation

/// One of the classic pastel sticky-note colors.
public enum NoteColor: String, Codable, CaseIterable, Sendable, Equatable {
    case yellow, pink, blue, green, purple, orange, gray, white

    public struct RGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Background color of the note body.
    public var background: RGB {
        switch self {
        case .yellow: RGB(red: 1.00, green: 0.96, blue: 0.62)
        case .pink:   RGB(red: 1.00, green: 0.82, blue: 0.86)
        case .blue:   RGB(red: 0.80, green: 0.94, blue: 0.99)
        case .green:  RGB(red: 0.83, green: 0.97, blue: 0.77)
        case .purple: RGB(red: 0.91, green: 0.84, blue: 1.00)
        case .orange: RGB(red: 1.00, green: 0.87, blue: 0.70)
        case .gray:   RGB(red: 0.91, green: 0.91, blue: 0.91)
        case .white:  RGB(red: 1.00, green: 1.00, blue: 1.00)
        }
    }

    /// Text color that reads well on the background.
    public var foreground: RGB {
        switch self {
        case .yellow: RGB(red: 0.36, green: 0.33, blue: 0.10)
        case .pink:   RGB(red: 0.42, green: 0.19, blue: 0.25)
        case .blue:   RGB(red: 0.10, green: 0.32, blue: 0.40)
        case .green:  RGB(red: 0.16, green: 0.36, blue: 0.13)
        case .purple: RGB(red: 0.30, green: 0.21, blue: 0.45)
        case .orange: RGB(red: 0.45, green: 0.28, blue: 0.08)
        case .gray:   RGB(red: 0.25, green: 0.25, blue: 0.25)
        case .white:  RGB(red: 0.15, green: 0.15, blue: 0.15)
        }
    }
}
