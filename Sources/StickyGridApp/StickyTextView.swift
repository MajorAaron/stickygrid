import AppKit

/// TextKit 1 text view with strikethrough and bullet-list actions.
/// Actions are @objc and nil-target-routable so Format menu items reach the
/// focused note via the responder chain; the toolbar calls them directly.
final class StickyTextView: NSTextView {

    static let bulletPrefix = "•\t"
    private static let bulletIndent: CGFloat = 22

    // MARK: Bold / italic

    @objc func noteToggleBold(_ sender: Any?) { toggleTrait(.boldFontMask) }
    @objc func noteToggleItalic(_ sender: Any?) { toggleTrait(.italicFontMask) }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let storage = textStorage else { return }
        let fontManager = NSFontManager.shared
        let range = selectedRange()
        let fallback = NSFont.userFont(ofSize: 14) ?? NSFont.systemFont(ofSize: 14)

        if range.length == 0 {
            let font = (typingAttributes[.font] as? NSFont) ?? fallback
            let has = fontManager.traits(of: font).contains(trait)
            typingAttributes[.font] = has
                ? fontManager.convert(font, toNotHaveTrait: trait)
                : fontManager.convert(font, toHaveTrait: trait)
            return
        }

        // Toggle direction comes from the first character so the whole
        // selection lands in one consistent state.
        let firstFont = (storage.attribute(.font, at: range.location,
                                           effectiveRange: nil) as? NSFont) ?? fallback
        let turningOn = !fontManager.traits(of: firstFont).contains(trait)

        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? fallback
            let newFont = turningOn
                ? fontManager.convert(font, toHaveTrait: trait)
                : fontManager.convert(font, toNotHaveTrait: trait)
            storage.addAttribute(.font, value: newFont, range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }

    // MARK: Strikethrough

    @objc func toggleStrikethrough(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let range = selectedRange()

        if range.length == 0 {
            let current = typingAttributes[.strikethroughStyle] as? Int ?? 0
            typingAttributes[.strikethroughStyle] =
                current == 0 ? NSUnderlineStyle.single.rawValue : 0
            return
        }

        guard shouldChangeText(in: range, replacementString: nil) else { return }
        let currentlyStruck = (storage.attribute(.strikethroughStyle, at: range.location,
                                                 effectiveRange: nil) as? Int ?? 0) != 0
        storage.beginEditing()
        if currentlyStruck {
            storage.removeAttribute(.strikethroughStyle, range: range)
        } else {
            storage.addAttribute(.strikethroughStyle,
                                 value: NSUnderlineStyle.single.rawValue, range: range)
        }
        storage.endEditing()
        didChangeText()
    }

    // MARK: Bullet list
    // Literal "•\t" markers + indented paragraph style. Deterministic across
    // RTF round-trips, unlike TextKit 1's NSTextList marker rendering.

    @objc func toggleBulletList(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let paragraphs = text.paragraphRange(for: selectedRange())
        let turningOn = !paragraphIsBulleted(at: paragraphs.location)

        guard shouldChangeText(in: paragraphs, replacementString: nil) else { return }
        storage.beginEditing()

        // Walk paragraphs back-to-front so earlier locations stay valid.
        var starts: [Int] = []
        var location = paragraphs.location
        while location < NSMaxRange(paragraphs) {
            let p = text.paragraphRange(for: NSRange(location: location, length: 0))
            starts.append(p.location)
            location = NSMaxRange(p)
            if p.length == 0 { break }
        }
        if starts.isEmpty { starts = [paragraphs.location] }

        for start in starts.reversed() {
            let hasMarker = paragraphHasMarker(at: start)
            if turningOn && !hasMarker {
                storage.replaceCharacters(
                    in: NSRange(location: start, length: 0),
                    with: NSAttributedString(string: Self.bulletPrefix,
                                             attributes: typingAttributes))
            } else if !turningOn && hasMarker {
                storage.replaceCharacters(
                    in: NSRange(location: start, length: Self.bulletPrefix.count), with: "")
            }
        }

        // Re-derive the affected range after edits, then set indentation.
        let newParagraphs = (storage.string as NSString)
            .paragraphRange(for: NSRange(location: paragraphs.location, length: 0))
        applyListIndent(turningOn, to: newParagraphs, storage: storage)

        storage.endEditing()
        didChangeText()
    }

    private func paragraphHasMarker(at start: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let text = storage.string as NSString
        guard start + Self.bulletPrefix.count <= text.length else { return false }
        return text.substring(with: NSRange(location: start, length: Self.bulletPrefix.count))
            == Self.bulletPrefix
    }

    private func paragraphIsBulleted(at location: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let text = storage.string as NSString
        guard text.length > 0 else { return false }
        let p = text.paragraphRange(for: NSRange(location: min(location, text.length), length: 0))
        return paragraphHasMarker(at: p.location)
    }

    private func applyListIndent(_ on: Bool, to range: NSRange, storage: NSTextStorage) {
        let style = NSMutableParagraphStyle()
        if let existing = (range.length > 0
            ? storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
            : typingAttributes[.paragraphStyle]) as? NSParagraphStyle {
            style.setParagraphStyle(existing)
        }
        style.headIndent = on ? Self.bulletIndent : 0
        style.firstLineHeadIndent = 0
        style.tabStops = [NSTextTab(textAlignment: .left, location: Self.bulletIndent)]
        if range.length > 0 {
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        typingAttributes[.paragraphStyle] = style
    }

    // MARK: Bullet continuation on return

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else { return super.insertNewline(sender) }
        let text = storage.string as NSString
        let caret = selectedRange()
        guard caret.length == 0, text.length > 0 else { return super.insertNewline(sender) }

        let paragraph = text.paragraphRange(for: caret)
        guard paragraphHasMarker(at: paragraph.location) else {
            return super.insertNewline(sender)
        }

        // Empty bullet + return = leave the list (like every notes app).
        let body = text.substring(with: paragraph)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if body == "•" {
            let markerRange = NSRange(location: paragraph.location,
                                      length: Self.bulletPrefix.count)
            if shouldChangeText(in: markerRange, replacementString: "") {
                storage.replaceCharacters(in: markerRange, with: "")
                didChangeText()
            }
            applyListIndent(false,
                            to: NSRange(location: markerRange.location, length: 0),
                            storage: storage)
            return
        }

        super.insertNewline(sender)
        insertText(Self.bulletPrefix, replacementRange: selectedRange())
    }
}
