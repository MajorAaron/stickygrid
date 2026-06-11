import AppKit
import StickyGridCore
import SwiftUI

/// The four arrangements offered by the layout palette.
enum NoteLayout: String, CaseIterable {
    case mosaic, evenGrid, columns, shuffle

    var title: String {
        switch self {
        case .mosaic: "Mosaic"
        case .evenGrid: "Grid"
        case .columns: "Columns"
        case .shuffle: "Shuffle"
        }
    }
}

/// Floating HUD shown by ⌘T: one glyph button per layout. Click or press
/// 1–4 to apply, arrows move the highlight, Return (or ⌘T again) applies the
/// highlighted layout, Esc or clicking away cancels.
final class LayoutPaletteController: NSObject, NSWindowDelegate {
    private final class PalettePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class PaletteState: ObservableObject {
        @Published var highlighted = 0
    }

    private var panel: PalettePanel?
    private let state = PaletteState()
    private var keyMonitor: Any?
    private var onChoose: ((NoteLayout) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(on screen: NSScreen, highlighting layout: NoteLayout,
              onChoose: @escaping (NoteLayout) -> Void) {
        dismiss()
        self.onChoose = onChoose
        state.highlighted = NoteLayout.allCases.firstIndex(of: layout) ?? 0

        let view = LayoutPaletteView(state: state) { [weak self] index in
            self?.apply(index)
        }
        let hosting = NSHostingController(rootView: view)
        let size = hosting.view.fittingSize

        let panel = PalettePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting
        panel.delegate = self

        // Assigning contentViewController can zero a borderless panel's frame.
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width, height: size.height), display: true)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)

        // Note: optional chaining flattens, so `self?.handle(event) ?? event`
        // would re-deliver events that handle() intentionally swallows.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// ⌘T while the palette is open re-applies the highlighted layout.
    func applyHighlighted() {
        apply(state.highlighted)
    }

    func dismiss() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        onChoose = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func apply(_ index: Int) {
        guard NoteLayout.allCases.indices.contains(index) else { return }
        let layout = NoteLayout.allCases[index]
        let choose = onChoose
        dismiss()
        choose?(layout)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isVisible else { return event }
        switch event.keyCode {
        case 53:  // esc
            dismiss()
            return nil
        case 36, 76:  // return / keypad enter
            applyHighlighted()
            return nil
        case 123:  // left arrow
            state.highlighted = (state.highlighted + NoteLayout.allCases.count - 1)
                % NoteLayout.allCases.count
            return nil
        case 124:  // right arrow
            state.highlighted = (state.highlighted + 1) % NoteLayout.allCases.count
            return nil
        default:
            if let chars = event.charactersIgnoringModifiers,
               let digit = Int(chars), (1...NoteLayout.allCases.count).contains(digit) {
                apply(digit - 1)
                return nil
            }
            return event
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    // MARK: SwiftUI content

    private struct LayoutPaletteView: View {
        @ObservedObject var state: PaletteState
        let onChoose: (Int) -> Void

        var body: some View {
            HStack(spacing: 14) {
                ForEach(Array(NoteLayout.allCases.enumerated()), id: \.offset) { index, layout in
                    VStack(spacing: 7) {
                        LayoutGlyph(layout: layout)
                            .frame(width: 96, height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.06)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        index == state.highlighted
                                            ? Color.accentColor : Color.primary.opacity(0.15),
                                        lineWidth: index == state.highlighted ? 2 : 1))
                        Text(layout.title)
                            .font(.system(size: 11, weight: .medium))
                        Text("\(index + 1)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onChoose(index) }
                    .onHover { hovering in
                        if hovering { state.highlighted = index }
                    }
                }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Miniature preview of a layout, drawn as normalized rounded rects.
    private struct LayoutGlyph: View {
        let layout: NoteLayout

        // (x, y, w, h) in unit space, y down.
        private var tiles: [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            switch layout {
            case .mosaic:
                [(0.00, 0.00, 0.40, 0.55), (0.44, 0.00, 0.26, 0.30),
                 (0.74, 0.00, 0.26, 0.30), (0.44, 0.34, 0.56, 0.21),
                 (0.00, 0.59, 0.30, 0.41), (0.34, 0.59, 0.38, 0.41),
                 (0.76, 0.59, 0.24, 0.41)]
            case .evenGrid:
                [(0.00, 0.00, 0.31, 0.46), (0.345, 0.00, 0.31, 0.46),
                 (0.69, 0.00, 0.31, 0.46), (0.00, 0.54, 0.31, 0.46),
                 (0.345, 0.54, 0.31, 0.46), (0.69, 0.54, 0.31, 0.46)]
            case .columns:
                [(0.00, 0.00, 0.31, 0.42), (0.00, 0.48, 0.31, 0.52),
                 (0.345, 0.00, 0.31, 0.28), (0.345, 0.34, 0.31, 0.36),
                 (0.345, 0.76, 0.31, 0.24), (0.69, 0.00, 0.31, 0.56),
                 (0.69, 0.62, 0.31, 0.38)]
            case .shuffle:
                [(0.04, 0.08, 0.26, 0.36), (0.42, 0.02, 0.24, 0.32),
                 (0.72, 0.12, 0.25, 0.34), (0.10, 0.56, 0.25, 0.38),
                 (0.45, 0.48, 0.23, 0.36), (0.72, 0.58, 0.25, 0.36)]
            }
        }

        var body: some View {
            GeometryReader { geo in
                let inset: CGFloat = 8
                let w = geo.size.width - inset * 2
                let h = geo.size.height - inset * 2
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: tile.2 * w, height: tile.3 * h)
                        .offset(x: inset + tile.0 * w, y: inset + tile.1 * h)
                }
            }
        }
    }
}
