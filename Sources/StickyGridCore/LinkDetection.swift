import Foundation

/// Finds clickable URLs in note text. NSDataDetector can't match custom
/// schemes, so this is a plain regex over the schemes notes care about:
/// `stickygrid://` (note-to-note links) and `http(s)://`. Ranges are UTF-16
/// NSRanges, ready for NSAttributedString attribute application.
public enum LinkDetection {
    public struct Match: Equatable, Sendable {
        public var range: NSRange
        public var url: URL

        public init(range: NSRange, url: URL) {
            self.range = range
            self.url = url
        }
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:stickygrid|https?)://\S+"#)

    /// Characters that end sentences around a URL rather than belonging to
    /// it: `(see https://x.test).` links `https://x.test`.
    private static let trailing = CharacterSet(charactersIn: ".,;:!?)]}>\"'")

    public static func matches(in text: String) -> [Match] {
        let nsText = text as NSString
        let whole = NSRange(location: 0, length: nsText.length)
        return pattern.matches(in: text, range: whole).compactMap { result in
            var range = result.range
            while range.length > 0,
                  let scalar = Unicode.Scalar(nsText.character(at: NSMaxRange(range) - 1)),
                  trailing.contains(scalar) {
                range.length -= 1
            }
            guard range.length > 0,
                  let url = URL(string: nsText.substring(with: range)) else { return nil }
            return Match(range: range, url: url)
        }
    }
}
