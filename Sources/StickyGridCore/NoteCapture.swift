import Foundation

/// A request to create a note from outside the app: the `stickygrid://` URL
/// scheme, the macOS Services menu, or the clipboard.
///
/// URL form: `stickygrid://new?text=...&title=...&color=pink&markdown=1`
/// - `text` (alias `body`): the note body, percent-encoded
/// - `title`: optional first line, placed above the body
/// - `color`: one of the `NoteColor` names; unknown values are ignored
/// - `markdown`: `1` or `true` styles the text via MarkdownImport on arrival
public struct CaptureRequest: Equatable, Sendable {
    public var text: String
    public var color: NoteColor?
    /// True when the capture's first line was explicitly chosen by the
    /// caller (the URL scheme's `title=` param) rather than derived from
    /// the body — auto-title must not stack a second title on it.
    public var hasExplicitTitle: Bool
    /// True when the caller marked the text as markdown to be styled on
    /// arrival. With an explicit `title=`, the title line is parsed too.
    public var markdown: Bool

    public init(text: String, color: NoteColor? = nil, hasExplicitTitle: Bool = false,
                markdown: Bool = false) {
        self.text = text
        self.color = color
        self.hasExplicitTitle = hasExplicitTitle
        self.markdown = markdown
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
        var markdown = false
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for item in components?.queryItems ?? [] {
            switch item.name.lowercased() {
            case "text", "body": body = item.value
            case "title": title = item.value
            case "color": color = item.value.flatMap { NoteColor(rawValue: $0.lowercased()) }
            case "markdown": markdown = ["1", "true"].contains(item.value?.lowercased())
            default: break
            }
        }

        let text = [title, body].compactMap(\.self).joined(separator: "\n")
        return CaptureRequest(text: text, color: color,
                              hasExplicitTitle: !(title ?? "").isEmpty,
                              markdown: markdown)
    }

    /// Builds a `stickygrid://new` URL — the exact inverse of `from(url:)`,
    /// used by the `sticky` CLI. Nil and empty parameters are omitted;
    /// nothing at all yields the bare empty-note URL. URLComponents does
    /// the percent-encoding.
    public static func captureURL(body: String?, title: String?, color: NoteColor?,
                                  markdown: Bool = false) -> URL {
        var components = URLComponents()
        components.scheme = "stickygrid"
        components.host = "new"
        var items: [URLQueryItem] = []
        if let title, !title.isEmpty { items.append(URLQueryItem(name: "title", value: title)) }
        if let body, !body.isEmpty { items.append(URLQueryItem(name: "text", value: body)) }
        if let color { items.append(URLQueryItem(name: "color", value: color.rawValue)) }
        if markdown { items.append(URLQueryItem(name: "markdown", value: "1")) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    /// Wraps pasteboard/selection text; nil if there is nothing but whitespace.
    public static func from(plainText: String?) -> CaptureRequest? {
        guard let trimmed = plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return CaptureRequest(text: trimmed)
    }
}
