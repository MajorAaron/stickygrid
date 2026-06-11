import AppKit
import StickyGridCore

/// Bridges toolbar/menu actions to the live NSTextView of one note,
/// and handles RTF in/out for persistence.
final class RichTextController {
    weak var textView: StickyTextView?

    // MARK: Formatting (logic lives in StickyTextView so the Format menu
    // reaches the focused note through the responder chain)

    func toggleBold() { textView?.noteToggleBold(nil) }
    func toggleItalic() { textView?.noteToggleItalic(nil) }
    func toggleUnderline() { textView?.underline(nil) }
    func toggleStrikethrough() { textView?.toggleStrikethrough(nil) }
    func toggleBulletList() { textView?.toggleBulletList(nil) }

    /// Re-fonts the entire note, preserving bold/italic per run.
    func applyFont(family: String, size: Double) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let fontManager = NSFontManager.shared
        let fallback = NSFont.systemFont(ofSize: size)
        let base = NSFont(name: family, size: size)
            ?? fontManager.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? fallback

        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0, tv.shouldChangeText(in: full, replacementString: nil) {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: full) { value, subrange, _ in
                var newFont = base
                if let old = value as? NSFont {
                    let traits = fontManager.traits(of: old)
                        .intersection([.boldFontMask, .italicFontMask])
                    if !traits.isEmpty {
                        newFont = fontManager.convert(base, toHaveTrait: traits)
                    }
                }
                storage.addAttribute(.font, value: newFont, range: subrange)
            }
            storage.endEditing()
            tv.didChangeText()
        }
        tv.typingAttributes[.font] = base
        tv.bodyFont = base  // didSet re-promotes the first paragraph at the new size
    }

    func applyTextColor(_ rgb: NoteColor.RGB) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let color = NSColor(rgb)
        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: color, range: full)
            storage.endEditing()
        }
        tv.typingAttributes[.foregroundColor] = color
        tv.insertionPointColor = color
    }

    // MARK: RTF round-trip

    func rtfData() -> Data? {
        guard let storage = textView?.textStorage, storage.length > 0 else { return Data() }
        return storage.rtf(from: NSRange(location: 0, length: storage.length),
                           documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    func loadRTF(_ data: Data) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard !data.isEmpty,
              let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else {
            return
        }
        storage.setAttributedString(attributed)
        tv.restyleHeader()  // setAttributedString skips didChangeText; also upgrades pre-header notes
    }

    func plainText() -> String {
        textView?.string ?? ""
    }
}
