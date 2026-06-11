import AppKit
import StickyGridCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NotePanel] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // .regular is essential when running as a bare binary (swift run):
        // without it the process gets no Dock icon, menu bar, or key windows.
        NSApp.setActivationPolicy(.regular)

        openHardcodedNote()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // M2: a single hardcoded note to verify the window shell.
    private func openHardcodedNote() {
        let panel = NotePanel(frame: NSRect(x: 400, y: 400, width: 340, height: 260))
        let container = NoteContainerView(color: .yellow)
        let hosting = DraggableHostingView(rootView: NoteContentView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container
        panel.makeKeyAndOrderFront(nil)
        windows.append(panel)
    }
}
