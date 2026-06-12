import Foundation

/// A request to raise an existing note from outside the app — the inverse
/// direction of `CaptureRequest`. URL form: `stickygrid://open?note=<query>`
/// (`id=` accepted as an alias). The query is resolved with the same matcher
/// as `sticky cat`: case-insensitive id-prefix (hyphens ignored) or title
/// substring.
public struct OpenRequest: Equatable, Sendable {
    public var query: String

    public init(query: String) {
        self.query = query
    }

    /// Parses a `stickygrid://open` URL; nil if it isn't one, or if the
    /// query is missing or empty — there's nothing to open.
    public static func from(url: URL) -> OpenRequest? {
        guard url.scheme?.lowercased() == "stickygrid" else { return nil }
        let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .lowercased()
        guard action == "open" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for item in components?.queryItems ?? [] where ["note", "id"].contains(item.name.lowercased()) {
            if let value = item.value, !value.isEmpty {
                return OpenRequest(query: value)
            }
        }
        return nil
    }

    /// Builds a `stickygrid://open` URL — the exact inverse of `from(url:)`,
    /// used by `sticky open`. URLComponents does the percent-encoding.
    public static func openURL(query: String) -> URL {
        var components = URLComponents()
        components.scheme = "stickygrid"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "note", value: query)]
        return components.url!
    }
}
