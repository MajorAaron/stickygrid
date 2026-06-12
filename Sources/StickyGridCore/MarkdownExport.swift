import Foundation

/// Serializes a note back to markdown — the inverse of MarkdownTyping. Pure
/// string logic: the app layer flattens NSTextStorage into styled runs per
/// paragraph and this emits the markdown. See
/// docs/superpowers/specs/2026-06-11-share-export-design.md.
public enum MarkdownExport {

    /// One same-styled stretch of a paragraph. Underline has no markdown
    /// equivalent, so it never reaches this layer.
    public struct Run: Equatable, Sendable {
        public var text: String
        public var bold: Bool
        public var italic: Bool
        public var strikethrough: Bool
        public var code: Bool

        public init(text: String, bold: Bool = false, italic: Bool = false,
                    strikethrough: Bool = false, code: Bool = false) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.strikethrough = strikethrough
            self.code = code
        }
    }

    /// The style flags of one attribute stretch, as judged by a caller's
    /// classifier — font-trait inspection is AppKit knowledge, so it stays
    /// out of Core and comes in through the closure.
    public struct Style: Equatable, Sendable {
        public var bold: Bool
        public var italic: Bool
        public var strikethrough: Bool
        public var code: Bool

        public init(bold: Bool = false, italic: Bool = false,
                    strikethrough: Bool = false, code: Bool = false) {
            self.bold = bold
            self.italic = italic
            self.strikethrough = strikethrough
            self.code = code
        }
    }

    /// Flattens an attributed string into per-paragraph styled runs. The
    /// first paragraph's bold is the auto-header style, not user emphasis,
    /// so it is dropped — that line exports as an H1 heading instead.
    public static func runs(
        of text: NSAttributedString,
        classify: ([NSAttributedString.Key: Any]) -> Style
    ) -> [[Run]] {
        guard text.length > 0 else { return [] }
        let string = text.string as NSString
        var paragraphs: [[Run]] = []
        var location = 0
        while location < string.length {
            var start = 0, end = 0, contentsEnd = 0
            string.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                     for: NSRange(location: location, length: 0))
            let content = NSRange(location: start, length: contentsEnd - start)
            paragraphs.append(runs(in: content, of: text, classify: classify,
                                   dropBold: paragraphs.isEmpty))
            location = end
        }
        return paragraphs
    }

    /// The whole attributed string as markdown.
    public static func markdown(
        of text: NSAttributedString,
        classify: ([NSAttributedString.Key: Any]) -> Style
    ) -> String {
        markdown(paragraphs: runs(of: text, classify: classify))
    }

    private static func runs(
        in range: NSRange, of text: NSAttributedString,
        classify: ([NSAttributedString.Key: Any]) -> Style, dropBold: Bool
    ) -> [Run] {
        guard range.length > 0 else { return [] }
        var out: [Run] = []
        text.enumerateAttributes(in: range) { attrs, subrange, _ in
            let style = classify(attrs)
            out.append(Run(
                text: (text.string as NSString).substring(with: subrange),
                bold: !dropBold && style.bold,
                italic: style.italic,
                strikethrough: style.strikethrough,
                code: style.code))
        }
        return out
    }

    /// `paragraphs[i]` is paragraph i's runs, line-marker literals included.
    /// The first paragraph is the note's title and exports as an H1 heading
    /// unless it is a list line or empty.
    public static func markdown(paragraphs: [[Run]]) -> String {
        paragraphs.enumerated()
            .map { index, runs in line(runs, isFirst: index == 0) }
            .joined(separator: "\n")
    }

    private static func line(_ runs: [Run], isFirst: Bool) -> String {
        var runs = runs
        var prefix = ""
        let plainLine = runs.map(\.text).joined()
        if let marker = MarkdownTyping.LineMarker.parse(paragraph: plainLine) {
            runs = strip(marker.literal.count, from: runs)
            prefix = markdownPrefix(for: marker)
        } else if isFirst, !plainLine.isEmpty {
            prefix = "# "
        }
        return prefix + serialize(runs)
    }

    private static func markdownPrefix(for marker: MarkdownTyping.LineMarker) -> String {
        switch marker {
        case .bullet: return "- "
        case .numbered(let n): return "\(n). "
        case .checkbox(let checked): return checked ? "- [x] " : "- [ ] "
        case .quote: return "> "
        }
    }

    /// Drops the marker literal off the front of the run list, wherever the
    /// run boundaries happen to fall.
    private static func strip(_ count: Int, from runs: [Run]) -> [Run] {
        var remaining = count
        var out: [Run] = []
        for var run in runs {
            if remaining > 0 {
                let dropped = min(remaining, run.text.count)
                run.text = String(run.text.dropFirst(dropped))
                remaining -= dropped
            }
            if !run.text.isEmpty { out.append(run) }
        }
        return out
    }

    private static func serialize(_ runs: [Run]) -> String {
        // Code spans drop the other flags (code stays literal, matching the
        // typing direction), and whitespace-only runs carry no visible style —
        // demoting them to plain lets "a"+" "+"b" runs merge cleanly.
        let normalized: [Run] = runs.compactMap { run in
            guard !run.text.isEmpty else { return nil }
            var r = run
            if r.code { r.bold = false; r.italic = false; r.strikethrough = false }
            if r.text.allSatisfy({ $0 == " " || $0 == "\t" }) { r = Run(text: r.text) }
            return r
        }

        // Merge adjacent same-styled runs so piecewise styling emits one
        // delimiter pair.
        var merged: [Run] = []
        for run in normalized {
            if var last = merged.last, sameFlags(last, run) {
                last.text += run.text
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        return merged.map(emit).joined()
    }

    private static func sameFlags(_ a: Run, _ b: Run) -> Bool {
        (a.bold, a.italic, a.strikethrough, a.code)
            == (b.bold, b.italic, b.strikethrough, b.code)
    }

    private static func emit(_ run: Run) -> String {
        guard run.bold || run.italic || run.strikethrough || run.code else {
            return run.text
        }
        // Whitespace inside the delimiters invalidates the markdown — hoist
        // run-edge spaces and tabs outside.
        let isPad: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        let lead = String(run.text.prefix(while: isPad))
        let trail = String(run.text.reversed().prefix(while: isPad).reversed())
        let core = String(run.text.dropFirst(lead.count).dropLast(trail.count))
        guard !core.isEmpty else { return run.text }

        var s = core
        if run.code {
            s = "`\(s)`"
        } else {
            if run.bold, run.italic {
                s = "***\(s)***"
            } else if run.bold {
                s = "**\(s)**"
            } else if run.italic {
                s = "*\(s)*"
            }
            if run.strikethrough { s = "~~\(s)~~" }
        }
        return lead + s + trail
    }
}
