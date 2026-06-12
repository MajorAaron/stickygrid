import AppKit
import StickyGridCore

/// Outbound serialization: flattens the live text storage into styled runs
/// and hands them to MarkdownExport in Core.
extension StickyTextView {

    /// The whole note as markdown. The first paragraph's bold is the
    /// auto-header style, not user emphasis, so it is dropped — the line
    /// exports as an H1 heading instead.
    func markdownText() -> String {
        guard let storage = textStorage, storage.length > 0 else { return "" }
        let text = storage.string as NSString
        var paragraphs: [[MarkdownExport.Run]] = []
        var location = 0
        while location < text.length {
            var start = 0, end = 0, contentsEnd = 0
            text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                   for: NSRange(location: location, length: 0))
            let content = NSRange(location: start, length: contentsEnd - start)
            paragraphs.append(runs(in: content, storage: storage,
                                   dropBold: paragraphs.isEmpty))
            location = end
        }
        return MarkdownExport.markdown(paragraphs: paragraphs)
    }

    private func runs(in range: NSRange, storage: NSTextStorage,
                      dropBold: Bool) -> [MarkdownExport.Run] {
        guard range.length > 0 else { return [] }
        let fontManager = NSFontManager.shared
        var out: [MarkdownExport.Run] = []
        storage.enumerateAttributes(in: range) { attrs, subrange, _ in
            let font = attrs[.font] as? NSFont
            let traits = font.map(fontManager.traits(of:)) ?? []
            let strike = attrs[.strikethroughStyle] as? Int ?? 0
            out.append(MarkdownExport.Run(
                text: (storage.string as NSString).substring(with: subrange),
                bold: !dropBold && traits.contains(.boldFontMask),
                italic: traits.contains(.italicFontMask),
                strikethrough: strike != 0,
                code: font?.fontName.hasPrefix(Self.codeFontName) ?? false))
        }
        return out
    }
}
