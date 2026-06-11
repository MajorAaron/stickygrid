import AppKit
import StickyGridCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: NoteStore!
    private var windowManager: WindowManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // .regular is essential when running as a bare binary (swift run):
        // without it the process gets no Dock icon, menu bar, or key windows.
        NSApp.setActivationPolicy(.regular)

        store = NoteStore()
        windowManager = WindowManager(store: store)
        NSApp.mainMenu = MainMenuBuilder.build(windowManager: windowManager)

        windowManager.restoreAll()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.flushNow()
        guard store.saveFailed else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Couldn't save your notes"
        alert.informativeText = "Some changes could not be written to disk."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
