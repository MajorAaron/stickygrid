import AppKit
import StickyGridCore

/// Inbound markdown conversion: turns MarkdownImport's parsed lines into
/// styled attributed text and inserts it at the selection. The paste
/// override in StickyTextView routes plain-text markdown pastes here.
extension StickyTextView {

    /// Inserts `markdown` at the current selection, converted to styled runs
    /// and native list markers. Goes through shouldChangeText/didChangeText
    /// so undo, autosave, and the header restyle fire normally; the marker
    /// literals and indent match the typed path, so return-key continuation
    /// and checkbox clicks work on pasted lists.
    func insertMarkdown(_ markdown: String) {
        guard let storage = textStorage, !markdown.isEmpty else { return }

        let newline = NSAttributedString(string: "\n", attributes: baseAttributes())
        let converted = NSMutableAttributedString()
        for (index, line) in MarkdownImport.parse(markdown).enumerated() {
            if index > 0 { converted.append(newline) }
            if let marker = line.marker {
                converted.append(NSAttributedString(string: marker.literal,
                                                    attributes: baseAttributes()))
            }
            for run in line.runs {
                converted.append(NSAttributedString(string: run.text,
                                                    attributes: attributes(for: run)))
            }
        }

        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: converted.string) else { return }
        breakUndoCoalescing()
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: converted)
        indentListParagraphs(
            in: NSRange(location: range.location, length: converted.length),
            storage: storage)
        storage.endEditing()
        didChangeText()
        setSelectedRange(NSRange(location: range.location + converted.length, length: 0))
    }

    /// Typing attributes with the font reset to the plain body font — the
    /// caret may carry header or user styling, and restyleHeader re-derives
    /// the first paragraph's look after the insert anyway.
    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        var attrs = typingAttributes
        attrs[.font] = bodyFont
        attrs[.strikethroughStyle] = nil
        return attrs
    }

    private func attributes(for run: MarkdownExport.Run) -> [NSAttributedString.Key: Any] {
        var attrs = baseAttributes()
        let fontManager = NSFontManager.shared
        var font = bodyFont
        if run.code {
            font = NSFont(name: Self.codeFontName, size: font.pointSize)
                ?? .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        } else {
            if run.bold { font = fontManager.convert(font, toHaveTrait: .boldFontMask) }
            if run.italic { font = fontManager.convert(font, toHaveTrait: .italicFontMask) }
        }
        attrs[.font] = font
        if run.strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    private func indentListParagraphs(in inserted: NSRange, storage: NSTextStorage) {
        let text = storage.string as NSString
        var location = inserted.location
        while location < NSMaxRange(inserted) {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            if MarkdownTyping.LineMarker.parse(
                paragraph: text.substring(with: paragraph)) != nil {
                applyListIndent(true, to: paragraph, storage: storage)
            }
            location = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        }
    }
}
