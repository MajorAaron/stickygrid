import AppKit
import SwiftUI

/// Hosting view that lets mouse-downs in non-interactive SwiftUI regions
/// drag the window (combined with the window's isMovableByWindowBackground).
/// The NSTextView inside opts out automatically, so text still selects.
/// Concrete over AnyView: a generic NSHostingView subclass crashes the
/// Swift 6.2.4 release-mode optimizer (EarlyPerfInliner, deinit).
final class DraggableHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { true }

    init(_ content: some View) {
        super.init(rootView: AnyView(content))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @available(*, unavailable)
    required init(rootView: AnyView) { fatalError("use init(_:)") }
}
