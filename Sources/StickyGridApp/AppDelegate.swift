import AppKit
import StickyGridCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: NoteStore!
    private var windowManager: WindowManager!
    private var servicesProvider: ServicesProvider?
    /// stickygrid:// URLs can arrive before didFinishLaunching; replayed after.
    private var pendingCaptureURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // .regular is essential when running as a bare binary (swift run):
        // without it the process gets no Dock icon, menu bar, or key windows.
        NSApp.setActivationPolicy(.regular)

        store = NoteStore()
        windowManager = WindowManager(store: store)
        NSApp.mainMenu = MainMenuBuilder.build(windowManager: windowManager)

        servicesProvider = ServicesProvider(windowManager: windowManager)
        NSApp.servicesProvider = servicesProvider

        windowManager.restoreAll()
        NSApp.activate(ignoringOtherApps: true)

        let queued = pendingCaptureURLs
        pendingCaptureURLs = []
        handleCapture(urls: queued)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard windowManager != nil else {
            pendingCaptureURLs.append(contentsOf: urls)
            return
        }
        handleCapture(urls: urls)
    }

    private func handleCapture(urls: [URL]) {
        for url in urls {
            guard let request = CaptureRequest.from(url: url) else {
                NSLog("StickyGrid: ignoring unrecognized URL \(url)")
                continue
            }
            windowManager.createNote(from: request)
        }
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
