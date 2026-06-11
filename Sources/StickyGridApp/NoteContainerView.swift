import AppKit
import StickyGridCore

extension NSColor {
    convenience init(_ rgb: NoteColor.RGB) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

/// The note window's root view: rounded, colored, clips its content.
final class NoteContainerView: NSView {
    private(set) var color: NoteColor

    init(color: NoteColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        applyColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func setColor(_ newColor: NoteColor) {
        color = newColor
        applyColor()
        window?.invalidateShadow()
    }

    private func applyColor() {
        layer?.backgroundColor = NSColor(color.background).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }
}
