import Foundation

/// A request to create a note from outside the app: the `stickygrid://` URL
/// scheme, the macOS Services menu, or the clipboard.
///
/// URL form: `stickygrid://new?text=...&title=...&color=pink`
/// - `text` (alias `body`): the note body, percent-encoded
/// - `title`: optional first line, placed above the body
/// - `color`: one of the `NoteColor` names; unknown values are ignored
public struct CaptureRequest: Equatable, Sendable {
    public var text: String
    public var color: NoteColor?
    /// True when the capture's first line was explicitly chosen by the
    /// caller (the URL scheme's `title=` param) rather than derived from
    /// the body — auto-title must not stack a second title on it.
    public var hasExplicitTitle: Bool

    public init(text: String, color: NoteColor? = nil, hasExplicitTitle: Bool = false) {
        self.text = text
        self.color = color
        self.hasExplicitTitle = hasExplicitTitle
    }

    /// First line of the text, capped to the stored snippet length.
    public var titleSnippet: String {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        return String(firstLine.prefix(40))
    }

    /// Parses a `stickygrid://new` URL; nil if the URL is not a capture URL.
    /// A bare `stickygrid://new` is valid and yields an empty note.
    public static func from(url: URL) -> CaptureRequest? {
        guard url.scheme?.lowercased() == "stickygrid" else { return nil }
        let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .lowercased()
        guard action == "new" else { return nil }

        var title: String?
        var body: String?
        var color: NoteColor?
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for item in components?.queryItems ?? [] {
            switch item.name.lowercased() {
            case "text", "body": body = item.value
            case "title": title = item.value
            case "color": color = item.value.flatMap { NoteColor(rawValue: $0.lowercased()) }
            default: break
            }
        }

        let text = [title, body].compactMap(\.self).joined(separator: "\n")
        return CaptureRequest(text: text, color: color,
                              hasExplicitTitle: !(title ?? "").isEmpty)
    }

    /// Wraps pasteboard/selection text; nil if there is nothing but whitespace.
    public static func from(plainText: String?) -> CaptureRequest? {
        guard let trimmed = plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return CaptureRequest(text: trimmed)
    }
}
