import AppKit
import StickyGridCore

/// TextKit 1 text view with strikethrough and bullet-list actions.
/// Actions are @objc and nil-target-routable so Format menu items reach the
/// focused note via the responder chain; the toolbar calls them directly.
final class StickyTextView: NSTextView {

    static let bulletPrefix = MarkdownTyping.LineMarker.bullet.literal
    private static let bulletIndent: CGFloat = 22

    /// Routes dropped .md files out of the view layer (drop handling in
    /// +Drop.swift); wired by RichTextEditor to WindowManager's import path.
    var onDropMarkdownFiles: (([URL]) -> Void)?

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

    // MARK: Auto first-line header
    // The first paragraph always renders as a header: bold, headerScale × the
    // note's body size. restyleHeader() re-asserts this invariant after every
    // edit; it never calls didChangeText, so it cannot recurse. Demotion of
    // oversized runs below the header is safe because the app has no per-run
    // size editing — only header-derived text is ever oversized.

    static let headerScale: CGFloat = 1.3

    /// The note's body font; the header style is derived from it. Set by
    /// RichTextEditor at creation and by RichTextController.applyFont.
    var bodyFont: NSFont = .userFont(ofSize: 14) ?? .systemFont(ofSize: 14) {
        didSet { restyleHeader() }
    }

    override func didChangeText() {
        super.didChangeText()
        restyleHeader()
        restyleLinks()
    }

    func restyleHeader() {
        guard let storage = textStorage else { return }
        let fontManager = NSFontManager.shared
        let headerSize = (bodyFont.pointSize * Self.headerScale).rounded()
        let text = storage.string as NSString

        func headerVariant(of font: NSFont) -> NSFont {
            fontManager.convert(fontManager.convert(font, toSize: headerSize),
                                toHaveTrait: .boldFontMask)
        }

        if text.length > 0 {
            let header = text.paragraphRange(for: NSRange(location: 0, length: 0))
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: header) { value, subrange, _ in
                let font = (value as? NSFont) ?? bodyFont
                storage.addAttribute(.font, value: headerVariant(of: font),
                                     range: subrange)
            }
            let rest = NSRange(location: NSMaxRange(header),
                               length: text.length - NSMaxRange(header))
            if rest.length > 0 {
                storage.enumerateAttribute(.font, in: rest) { value, subrange, _ in
                    guard let font = value as? NSFont,
                          font.pointSize > bodyFont.pointSize else { return }
                    storage.addAttribute(
                        .font,
                        value: fontManager.convert(font, toSize: bodyFont.pointSize),
                        range: subrange)
                }
            }
            storage.endEditing()
        }

        // Keep typing attributes in step with the caret's paragraph so newly
        // typed text never appears at the wrong size.
        let caret = min(selectedRange().location, text.length)
        let inHeader = text.length == 0
            || text.paragraphRange(for: NSRange(location: caret, length: 0)).location == 0
        let typingFont = (typingAttributes[.font] as? NSFont) ?? bodyFont
        if inHeader {
            typingAttributes[.font] = headerVariant(of: typingFont)
        } else if typingFont.pointSize > bodyFont.pointSize {
            // Inherited from the header: body size, bold off — fresh typing on
            // a body line should look like body text. User-applied bold is at
            // body size and never enters this branch.
            let demoted = fontManager.convert(typingFont, toSize: bodyFont.pointSize)
            typingAttributes[.font] = fontManager.convert(demoted,
                                                          toNotHaveTrait: .boldFontMask)
        }
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

    func applyListIndent(_ on: Bool, to range: NSRange, storage: NSTextStorage) {
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

    // MARK: Markdown typing shortcuts (conversion logic in +Markdown.swift)

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        let typed = (insertString as? String)
            ?? (insertString as? NSAttributedString)?.string ?? ""
        // Single keystrokes only: pasted text and programmatic inserts (list
        // continuation markers) must not trigger conversion.
        guard typed.count == 1 else { return }
        convertMarkdownIfNeeded(afterTyping: typed)
    }

    // MARK: Markdown paste (conversion logic in +Import.swift)
    // Plain-text pastes that contain markdown convert to styled runs; rich
    // (RTF) pastes and plain pastes with no markdown keep default behavior.

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        if !types.contains(.rtf), !types.contains(.rtfd),
           let text = pasteboard.string(forType: .string),
           MarkdownImport.detectsMarkdown(text) {
            insertMarkdown(text)
            return
        }
        super.paste(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if let index = checkboxIndex(at: event), toggleCheckbox(at: index) { return }
        super.mouseDown(with: event)
    }

    // MARK: List continuation on return
    // Bullets repeat, numbered items increment, checkboxes continue
    // unchecked. Continuation markers are inserted via insertText but are
    // multi-character, so the markdown conversion hook ignores them.

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else { return super.insertNewline(sender) }
        let text = storage.string as NSString
        let caret = selectedRange()
        guard caret.length == 0, text.length > 0 else { return super.insertNewline(sender) }

        let paragraph = text.paragraphRange(for: caret)
        guard let marker = MarkdownTyping.LineMarker.parse(
            paragraph: text.substring(with: paragraph)) else {
            return super.insertNewline(sender)
        }

        // Empty item + return = leave the list (like every notes app).
        let body = text.substring(with: paragraph)
            .dropFirst(marker.literal.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            let markerRange = NSRange(location: paragraph.location,
                                      length: (marker.literal as NSString).length)
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
        insertText(marker.continuationLiteral, replacementRange: selectedRange())
    }
}
