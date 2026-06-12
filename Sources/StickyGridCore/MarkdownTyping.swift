import Foundation

/// Live markdown typing shortcuts: pure pattern detection consumed by
/// StickyTextView's conversion-on-type glue. All ranges are UTF-16 offsets
/// relative to the paragraph string, ready for NSTextStorage math.
/// See docs/superpowers/specs/2026-06-11-markdown-typing-design.md.
public enum MarkdownTyping {

    // MARK: Inline styles

    public enum InlineStyle: Equatable, Sendable {
        case bold, italic, strikethrough, code
    }

    public struct InlineMatch: Equatable, Sendable {
        /// The whole pattern including markers.
        public let fullRange: NSRange
        /// The content between the markers.
        public let contentRange: NSRange
        public let style: InlineStyle

        public init(fullRange: NSRange, contentRange: NSRange, style: InlineStyle) {
            self.fullRange = fullRange
            self.contentRange = contentRange
            self.style = style
        }
    }

    /// Longest first so `**` wins over `*`.
    private static let inlineMarkers: [(marker: String, style: InlineStyle)] = [
        ("**", .bold), ("~~", .strikethrough), ("*", .italic), ("`", .code),
    ]

    /// Returns the inline pattern whose closing delimiter ends exactly at
    /// `caret`, or nil. Call after a delimiter character is typed; only text
    /// before the caret is considered.
    public static func inlineMatch(paragraph: String, caret: Int) -> InlineMatch? {
        let text = paragraph as NSString
        guard caret <= text.length else { return nil }
        for (marker, style) in inlineMarkers {
            let len = (marker as NSString).length
            guard caret >= 2 * len + 1 else { continue }  // marker + content + marker
            let closerStart = caret - len
            guard text.substring(with: NSRange(location: closerStart, length: len)) == marker
            else { continue }
            // Nearest opener first; walk outward until one validates.
            var search = NSRange(location: 0, length: closerStart)
            while true {
                let opener = text.range(of: marker, options: .backwards, range: search)
                guard opener.location != NSNotFound else { break }
                if let match = validated(text: text, opener: opener, closerStart: closerStart,
                                         marker: marker, style: style, caret: caret) {
                    return match
                }
                search.length = opener.location
            }
        }
        return nil
    }

    private static func validated(
        text: NSString, opener: NSRange, closerStart: Int,
        marker: String, style: InlineStyle, caret: Int
    ) -> InlineMatch? {
        let content = NSRange(location: NSMaxRange(opener),
                              length: closerStart - NSMaxRange(opener))
        guard content.length > 0 else { return nil }
        let body = text.substring(with: content)
        // No whitespace directly inside the markers, and no marker inside the
        // content — the latter rejects the "*bold*"-shaped tail of a
        // half-typed "**bold**".
        let whitespace = CharacterSet.whitespaces
        guard let first = body.unicodeScalars.first, !whitespace.contains(first),
              let last = body.unicodeScalars.last, !whitespace.contains(last),
              !body.contains(marker)
        else { return nil }
        // The opener must sit at a word boundary: paragraph start, whitespace,
        // or punctuation — never a letter/digit, and never the marker's own
        // character (that's the tail of a longer, still-open delimiter).
        if opener.location > 0 {
            let prev = text.character(at: opener.location - 1)
            if prev == marker.utf16.first { return nil }
            if let scalar = Unicode.Scalar(prev),
               CharacterSet.alphanumerics.contains(scalar) { return nil }
        }
        return InlineMatch(
            fullRange: NSRange(location: opener.location, length: caret - opener.location),
            contentRange: content,
            style: style)
    }

    // MARK: Line markers
    // Literal marker text + indent is the app's list representation (it
    // round-trips RTF deterministically — see the bullet design note in
    // StickyTextView). One type covers list conversion, return-key
    // continuation, and checkbox toggling.

    public enum LineMarker: Equatable, Sendable {
        case bullet
        case numbered(Int)
        case checkbox(checked: Bool)
        case quote

        /// The literal marker text at the start of the paragraph.
        public var literal: String {
            switch self {
            case .bullet: return "\u{2022}\t"                       // •
            case .numbered(let n): return "\(n).\t"
            case .checkbox(let checked): return checked ? "\u{2611}\t" : "\u{2610}\t"  // ☑ / ☐
            case .quote: return "\u{258E}\t"                        // ▎ quote bar
            }
        }

        /// The marker the return key starts the next line with.
        public var continuationLiteral: String {
            switch self {
            case .bullet: return LineMarker.bullet.literal
            case .numbered(let n): return LineMarker.numbered(n + 1).literal
            case .checkbox: return LineMarker.checkbox(checked: false).literal
            case .quote: return LineMarker.quote.literal
            }
        }

        /// Parses the marker at the start of a paragraph, if any.
        public static func parse(paragraph: String) -> LineMarker? {
            if paragraph.hasPrefix(LineMarker.bullet.literal) { return .bullet }
            if paragraph.hasPrefix("\u{2610}\t") { return .checkbox(checked: false) }
            if paragraph.hasPrefix("\u{2611}\t") { return .checkbox(checked: true) }
            if paragraph.hasPrefix(LineMarker.quote.literal) { return .quote }
            let digits = paragraph.prefix(while: { ("0"..."9").contains($0) })
            guard !digits.isEmpty,
                  paragraph.dropFirst(digits.count).hasPrefix(".\t"),
                  let n = Int(digits)
            else { return nil }
            return .numbered(n)
        }
    }

    // MARK: List triggers

    /// `linePrefix` is the paragraph text from its start through the caret,
    /// including the just-typed space. A trigger fires only when the marker
    /// syntax is the entire prefix — i.e. typed at the paragraph start.
    public static func listTrigger(linePrefix: String) -> LineMarker? {
        switch linePrefix {
        case "- ", "* ": return .bullet
        case "> ": return .quote
        case "[ ] ", "[] ": return .checkbox(checked: false)
        case "[x] ", "[X] ": return .checkbox(checked: true)
        default:
            guard linePrefix.hasSuffix(". ") else { return nil }
            let digits = linePrefix.dropLast(2)
            guard !digits.isEmpty,
                  digits.allSatisfy({ ("0"..."9").contains($0) }),
                  let n = Int(digits)
            else { return nil }
            return .numbered(n)
        }
    }

    /// `- ` becomes a bullet the moment its space lands, so the canonical
    /// markdown checkbox `- [ ] ` arrives as `[ ] ` typed on a fresh bullet.
    /// `textAfterBulletMarker` is the text between the bullet marker and the
    /// caret; an exact checkbox syntax upgrades the bullet.
    public static func checkboxUpgrade(afterBullet textAfterBulletMarker: String) -> LineMarker? {
        switch textAfterBulletMarker {
        case "[ ] ", "[] ": return .checkbox(checked: false)
        case "[x] ", "[X] ": return .checkbox(checked: true)
        default: return nil
        }
    }
}
