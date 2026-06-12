import AppKit
import StickyGridCore

/// Outbound serialization: MarkdownExport in Core walks the text storage;
/// this layer only classifies font attributes into style flags.
extension StickyTextView {

    /// The whole note as markdown. The first paragraph's bold is the
    /// auto-header style, not user emphasis, so Core drops it — the line
    /// exports as an H1 heading instead.
    func markdownText() -> String {
        guard let storage = textStorage, storage.length > 0 else { return "" }
        let fontManager = NSFontManager.shared
        return MarkdownExport.markdown(of: storage) { attrs in
            let font = attrs[.font] as? NSFont
            let traits = font.map(fontManager.traits(of:)) ?? []
            let strike = attrs[.strikethroughStyle] as? Int ?? 0
            return MarkdownExport.Style(
                bold: traits.contains(.boldFontMask),
                italic: traits.contains(.italicFontMask),
                strikethrough: strike != 0,
                code: font?.fontName.hasPrefix(Self.codeFontName) ?? false)
        }
    }
}
