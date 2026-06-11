import AppKit
import StickyGridCore

/// Target of the "New Sticky Note from Selection" entry in the macOS
/// Services menu (declared under NSServices in the app's Info.plist).
final class ServicesProvider: NSObject {
    private let windowManager: WindowManager

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    @objc func newNoteFromSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let request = CaptureRequest.from(
            plainText: pasteboard.string(forType: .string)) else {
            error.pointee = "The selection contains no text."
            return
        }
        windowManager.createNote(from: request)
    }
}
