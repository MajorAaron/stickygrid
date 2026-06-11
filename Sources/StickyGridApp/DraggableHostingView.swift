import AppKit
import SwiftUI

/// Hosting view that lets mouse-downs in non-interactive SwiftUI regions
/// drag the window (combined with the window's isMovableByWindowBackground).
/// The NSTextView inside opts out automatically, so text still selects.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}
