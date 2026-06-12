import AppKit
import StickyGridCore

// Clickable links. Like restyleHeader, restyleLinks re-asserts an invariant
// after every edit — the .link attribute covers exactly the textual URLs in
// the note — and never calls didChangeText, so it cannot recurse. Recomputing
// from the visible text means links broken by edits lose their attribute and
// stale persisted links self-heal on load.
extension StickyTextView {

    func restyleLinks() {
        guard let storage = textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.link, range: whole)
        for match in LinkDetection.matches(in: storage.string) {
            storage.addAttribute(.link, value: match.url, range: match.range)
        }
        storage.endEditing()
        // Typing after a link must not extend it visually.
        typingAttributes[.link] = nil
    }
}
