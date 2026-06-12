import AppKit
import StickyGridCore
import SwiftUI

/// Floating capture palette summoned by the global hotkey (⌃⌥N by default):
/// type a note from inside any app, pick a color, and ⌘↩ files it as a new
/// sticky without switching apps. Esc cancels; clicking away keeps the draft
/// for the next summon so an accidental dismissal never loses text.
final class QuickCaptureController: NSObject, NSWindowDelegate {
    private final class PalettePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class CaptureState: ObservableObject {
        @Published var text = ""
        @Published var color: NoteColor = .yellow
    }

    private static let colorKey = "QuickCaptureColor"

    private var panel: PalettePanel?
    private let state = CaptureState()
    private var keyMonitor: Any?
    private var onCapture: ((CaptureRequest) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(on screen: NSScreen, onCapture: @escaping (CaptureRequest) -> Void) {
        // The hotkey also has a menu equivalent; if both fire, the second
        // summon must not blow away the panel the first one just opened.
        if isVisible {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        self.onCapture = onCapture
        state.color = UserDefaults.standard.string(forKey: Self.colorKey)
            .flatMap { NoteColor(rawValue: $0) } ?? .yellow

        let view = QuickCaptureView(state: state)
        let hosting = NSHostingController(rootView: view)

        let width: CGFloat = 460
        let height: CGFloat = 196
        let panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        panel.delegate = self

        let visible = screen.visibleFrame
        panel.setFrame(NSRect(
            x: visible.midX - width / 2,
            y: visible.minY + visible.height * 0.72 - height,
            width: width, height: height), display: true)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// Hides the panel. The draft text survives unless `discardDraft` —
    /// only Esc and a successful capture throw it away.
    private func dismiss(discardDraft: Bool) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if discardDraft { state.text = "" }
        onCapture = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func capture() {
        guard let request = CaptureRequest.from(plainText: state.text) else {
            NSSound.beep()
            return
        }
        var colored = request
        colored.color = state.color
        UserDefaults.standard.set(state.color.rawValue, forKey: Self.colorKey)
        let onCapture = onCapture
        dismiss(discardDraft: true)
        onCapture?(colored)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isVisible, event.window === panel else { return event }
        switch event.keyCode {
        case 53:  // esc
            dismiss(discardDraft: true)
            return nil
        case 36, 76:  // return / keypad enter — only ⌘↩ captures
            guard event.modifierFlags.contains(.command) else { return event }
            capture()
            return nil
        default:
            return event
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss(discardDraft: false)
    }

    // MARK: SwiftUI content

    private struct QuickCaptureView: View {
        @ObservedObject var state: CaptureState
        @FocusState private var fieldFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Quick Capture", systemImage: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(NoteColor.allCases, id: \.self) { color in
                            ColorDot(color: color, selected: color == state.color)
                                .onTapGesture { state.color = color }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 36)

                Divider()

                TextEditor(text: $state.text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .focused($fieldFocused)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .frame(height: 124)

                Divider()
                HStack {
                    Text("First line becomes the title")
                    Spacer()
                    Text("⌘↩ Create Note   esc Cancel")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 28)
            }
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .onAppear {
                // The panel becomes key asynchronously; focus after that.
                DispatchQueue.main.async { fieldFocused = true }
            }
        }
    }

    private struct ColorDot: View {
        let color: NoteColor
        let selected: Bool

        var body: some View {
            let rgb = color.background
            Circle()
                .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                .overlay(Circle().strokeBorder(
                    selected ? Color.accentColor : Color.black.opacity(0.15),
                    lineWidth: selected ? 2 : 1))
                .frame(width: 16, height: 16)
        }
    }
}
