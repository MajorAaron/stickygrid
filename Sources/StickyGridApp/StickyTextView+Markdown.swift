import AppKit
import StickyGridCore

/// Live markdown conversion: typing `**bold**`, `*italic*`, `~~strike~~`, or
/// `` `code` `` converts in place the moment the closing delimiter lands.
/// Markers vanish; breakUndoCoalescing means one ⌘Z restores them. Every
/// change goes through shouldChangeText/didChangeText so undo, autosave, and
/// the header restyle fire normally.
extension StickyTextView {

    static let codeFontName = "Menlo"

    func convertMarkdownIfNeeded(afterTyping typed: String) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let caret = selectedRange().location
        guard caret <= text.length else { return }
        let paragraph = text.paragraphRange(for: NSRange(location: caret, length: 0))
        let paragraphText = text.substring(with: paragraph)
        let caretInParagraph = caret - paragraph.location

        switch typed {
        case "*", "~", "`":
            guard let match = MarkdownTyping.inlineMatch(
                paragraph: paragraphText, caret: caretInParagraph) else { return }
            applyInline(match, paragraphStart: paragraph.location)
        case " ":
            let prefix = (paragraphText as NSString).substring(to: caretInParagraph)
            if MarkdownTyping.LineMarker.parse(paragraph: paragraphText) == nil,
               let marker = MarkdownTyping.listTrigger(linePrefix: prefix) {
                applyListMarker(marker, replacing: NSRange(location: paragraph.location,
                                                           length: caretInParagraph))
            } else if prefix.hasPrefix(Self.bulletPrefix),
                      let marker = MarkdownTyping.checkboxUpgrade(
                          afterBullet: String(prefix.dropFirst(Self.bulletPrefix.count))) {
                applyListMarker(marker, replacing: NSRange(location: paragraph.location,
                                                           length: caretInParagraph))
            }
        default:
            return
        }
    }

    private func applyInline(_ match: MarkdownTyping.InlineMatch, paragraphStart: Int) {
        guard let storage = textStorage else { return }
        let full = NSRange(location: paragraphStart + match.fullRange.location,
                           length: match.fullRange.length)
        let content = NSRange(location: paragraphStart + match.contentRange.location,
                              length: match.contentRange.length)

        // Patterns typed inside an existing code span stay literal.
        if let font = storage.attribute(.font, at: full.location,
                                        effectiveRange: nil) as? NSFont,
           font.fontName.hasPrefix(Self.codeFontName) { return }

        let styled = NSMutableAttributedString(
            attributedString: storage.attributedSubstring(from: content))
        let styledRange = NSRange(location: 0, length: styled.length)
        let fontManager = NSFontManager.shared
        switch match.style {
        case .bold, .italic:
            let trait: NSFontTraitMask = match.style == .bold ? .boldFontMask : .italicFontMask
            styled.enumerateAttribute(.font, in: styledRange) { value, subrange, _ in
                let font = (value as? NSFont) ?? bodyFont
                styled.addAttribute(.font, value: fontManager.convert(font, toHaveTrait: trait),
                                    range: subrange)
            }
        case .strikethrough:
            styled.addAttribute(.strikethroughStyle,
                                value: NSUnderlineStyle.single.rawValue, range: styledRange)
        case .code:
            // Per-run size so a code span on the header line stays header-sized.
            styled.enumerateAttribute(.font, in: styledRange) { value, subrange, _ in
                let size = ((value as? NSFont) ?? bodyFont).pointSize
                let mono = NSFont(name: Self.codeFontName, size: size)
                    ?? .monospacedSystemFont(ofSize: size, weight: .regular)
                styled.addAttribute(.font, value: mono, range: subrange)
            }
        }

        guard shouldChangeText(in: full, replacementString: styled.string) else { return }
        // The just-typed delimiter carried plain typing attributes; saving and
        // restoring them keeps typing unstyled after the converted run.
        let savedTyping = typingAttributes
        breakUndoCoalescing()
        storage.beginEditing()
        storage.replaceCharacters(in: full, with: styled)
        storage.endEditing()
        didChangeText()
        setSelectedRange(NSRange(location: full.location + styled.length, length: 0))
        typingAttributes = savedTyping
    }

    private func applyListMarker(_ marker: MarkdownTyping.LineMarker,
                                 replacing typedRange: NSRange) {
        guard let storage = textStorage else { return }
        let literal = marker.literal
        guard shouldChangeText(in: typedRange, replacementString: literal) else { return }
        breakUndoCoalescing()
        storage.beginEditing()
        storage.replaceCharacters(
            in: typedRange,
            with: NSAttributedString(string: literal, attributes: typingAttributes))
        storage.endEditing()
        let paragraph = (storage.string as NSString)
            .paragraphRange(for: NSRange(location: typedRange.location, length: 0))
        applyListIndent(true, to: paragraph, storage: storage)
        didChangeText()
        setSelectedRange(NSRange(location: typedRange.location + (literal as NSString).length,
                                 length: 0))
    }
}
