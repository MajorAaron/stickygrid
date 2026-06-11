import AppKit

/// Borderless, rounded, resizable window hosting one sticky note.
/// NSWindow (not NSPanel): panels hide on deactivate, which sticky notes must not.
final class NotePanel: NSWindow {
    // Borderless windows refuse keyboard focus without these.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        // The WindowManager dictionary owns this window's lifetime.
        isReleasedWhenClosed = false
        isRestorable = false
        collectionBehavior = [.fullScreenNone, .managed]
        acceptsMouseMovedEvents = true
        minSize = NSSize(width: 160, height: 120)
    }
}
