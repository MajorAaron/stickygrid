import Foundation

/// Parses pasted markdown into styled runs and native line markers — the
/// inverse of MarkdownExport, reusing its Run type and MarkdownTyping's
/// LineMarker. Pure string logic; the app layer turns lines into attributed
/// text. See docs/superpowers/specs/2026-06-11-markdown-paste-design.md.
public enum MarkdownImport {

    public struct Line: Equatable, Sendable {
        public var marker: MarkdownTyping.LineMarker?
        public var runs: [MarkdownExport.Run]

        public init(marker: MarkdownTyping.LineMarker? = nil,
                    runs: [MarkdownExport.Run]) {
            self.marker = marker
            self.runs = runs
        }
    }

    public static func parse(_ markdown: String) -> [Line] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .map { parseLine(String($0)) }
    }

    /// True when the text contains anything paste conversion would change —
    /// the app falls back to a plain paste otherwise.
    public static func detectsMarkdown(_ markdown: String) -> Bool {
        parse(markdown).contains { line in
            line.marker != nil || line.runs.contains {
                $0.bold || $0.italic || $0.strikethrough || $0.code
            }
        }
    }

    // MARK: Lines

    private static func parseLine(_ line: String) -> Line {
        if let (marker, rest) = lineMarker(line) {
            return Line(marker: marker, runs: runs(in: rest))
        }
        if let rest = headingBody(line) {
            return Line(marker: nil, runs: runs(in: rest).map { run in
                var r = run
                if !r.code { r.bold = true }
                return r
            })
        }
        return Line(marker: nil, runs: runs(in: line))
    }

    private static func lineMarker(_ line: String) -> (MarkdownTyping.LineMarker, String)? {
        for bullet in ["- ", "* "] {
            guard line.hasPrefix(bullet) else { continue }
            let rest = String(line.dropFirst(bullet.count))
            for (box, checked) in [("[ ] ", false), ("[] ", false),
                                   ("[x] ", true), ("[X] ", true)] {
                if rest.hasPrefix(box) {
                    return (.checkbox(checked: checked), String(rest.dropFirst(box.count)))
                }
            }
            return (.bullet, rest)
        }
        if line.hasPrefix("> ") {
            return (.quote, String(line.dropFirst(2)))
        }
        let digits = line.prefix(while: { ("0"..."9").contains($0) })
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". "),
           let n = Int(digits) {
            return (.numbered(n), String(line.dropFirst(digits.count + 2)))
        }
        return nil
    }

    private static func headingBody(_ line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).hasPrefix(" ") else { return nil }
        return String(line.dropFirst(hashes.count + 1))
    }

    // MARK: Inline spans

    private struct Flags {
        var bold = false, italic = false, strikethrough = false
    }

    /// Longest first so `***` wins over `**` wins over `*`; code first so
    /// backtick spans shield their content from further parsing.
    private static let delimiters: [(marker: String, bold: Bool, italic: Bool, strike: Bool)] = [
        ("***", true, true, false), ("**", true, false, false),
        ("~~", false, false, true), ("*", false, true, false),
    ]

    private static func runs(in text: String) -> [MarkdownExport.Run] {
        var out: [MarkdownExport.Run] = []
        scan(Array(text), flags: Flags(), into: &out)
        return out
    }

    /// Walks the characters once, emitting literal text and recursing into
    /// validated spans with the span's style OR-ed onto `flags`.
    private static func scan(_ chars: [Character], flags: Flags,
                             into out: inout [MarkdownExport.Run]) {
        var literal = ""
        var i = 0

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            out.append(MarkdownExport.Run(
                text: literal, bold: flags.bold, italic: flags.italic,
                strikethrough: flags.strikethrough))
            literal = ""
        }

        while i < chars.count {
            if chars[i] == "`", openerBoundary(chars, at: i),
               let close = closer(chars, marker: ["`"], from: i + 1) {
                flushLiteral()
                out.append(MarkdownExport.Run(
                    text: String(chars[(i + 1)..<close]), code: true))
                i = close + 1
                continue
            }
            if let (marker, span) = matchSpan(chars, at: i) {
                flushLiteral()
                var inner = flags
                inner.bold = inner.bold || marker.bold
                inner.italic = inner.italic || marker.italic
                inner.strikethrough = inner.strikethrough || marker.strike
                scan(Array(chars[(i + marker.marker.count)..<span]),
                     flags: inner, into: &out)
                i = span + marker.marker.count
                continue
            }
            literal.append(chars[i])
            i += 1
        }
        flushLiteral()
    }

    private static func matchSpan(
        _ chars: [Character], at i: Int
    ) -> (marker: (marker: String, bold: Bool, italic: Bool, strike: Bool), contentEnd: Int)? {
        guard openerBoundary(chars, at: i) else { return nil }
        for delim in delimiters {
            let m = Array(delim.marker)
            guard i + m.count <= chars.count,
                  Array(chars[i..<(i + m.count)]) == m,
                  let close = closer(chars, marker: m, from: i + m.count)
            else { continue }
            return (delim, close)
        }
        return nil
    }

    /// The opener must sit at a word boundary — start of line, whitespace,
    /// or punctuation, never a letter/digit (mirrors MarkdownTyping).
    private static func openerBoundary(_ chars: [Character], at i: Int) -> Bool {
        guard i > 0 else { return true }
        return !(chars[i - 1].isLetter || chars[i - 1].isNumber)
    }

    /// Index where valid closing `marker` content ends, or nil. Content must
    /// be non-empty with no whitespace just inside either delimiter.
    private static func closer(_ chars: [Character], marker: [Character],
                               from start: Int) -> Int? {
        guard start < chars.count, !chars[start].isWhitespace else { return nil }
        var i = start + 1
        while i + marker.count <= chars.count {
            if Array(chars[i..<(i + marker.count)]) == marker,
               !chars[i - 1].isWhitespace {
                return i
            }
            i += 1
        }
        return nil
    }
}
