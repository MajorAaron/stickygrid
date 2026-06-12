import AppKit
import StickyGridCore
import SwiftUI

/// Floating search palette shown by ⌘F: type to live-search every note,
/// ↑/↓ move the highlight, Return jumps to the highlighted note, Esc or
/// clicking away cancels.
final class SearchPaletteController: NSObject, NSWindowDelegate {
    private final class PalettePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class PaletteState: ObservableObject {
        @Published var query = ""
        @Published var results: [NoteSearch.Match] = []
        @Published var highlighted = 0
    }

    private var panel: PalettePanel?
    private let state = PaletteState()
    private var keyMonitor: Any?
    private var search: ((String) -> [NoteSearch.Match])?
    private var onChoose: ((NoteSearch.Match) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(on screen: NSScreen,
              search: @escaping (String) -> [NoteSearch.Match],
              onChoose: @escaping (NoteSearch.Match) -> Void) {
        dismiss()
        self.search = search
        self.onChoose = onChoose
        state.query = ""
        state.results = []
        state.highlighted = 0

        let view = SearchPaletteView(state: state,
                                     onQueryChange: { [weak self] query in
                                         self?.queryChanged(query)
                                     },
                                     onChoose: { [weak self] index in
                                         self?.choose(index)
                                     })
        let hosting = NSHostingController(rootView: view)

        let width: CGFloat = 460
        let panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 56),
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

        // Spotlight-style placement: centered, in the upper third. The
        // SwiftUI content grows downward as results appear, so anchor by
        // the top edge (see windowDidResize-free sizing in the view).
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(
            x: visible.midX - width / 2,
            y: visible.minY + visible.height * 0.72 - 56,
            width: width, height: 56), display: true)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func dismiss() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        search = nil
        onChoose = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func queryChanged(_ query: String) {
        state.results = search?(query) ?? []
        state.highlighted = 0
        resizeToFit()
    }

    /// Grow downward from the anchored top edge as results come and go.
    private func resizeToFit() {
        guard let panel, let hosting = panel.contentViewController else { return }
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        let top = panel.frame.maxY
        panel.setFrame(NSRect(
            x: panel.frame.minX, y: top - size.height,
            width: panel.frame.width, height: size.height), display: true)
    }

    private func choose(_ index: Int) {
        guard state.results.indices.contains(index) else { return }
        let match = state.results[index]
        let choose = onChoose
        dismiss()
        choose?(match)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isVisible, event.window === panel else { return event }
        switch event.keyCode {
        case 53:  // esc
            dismiss()
            return nil
        case 36, 76:  // return / keypad enter
            choose(state.highlighted)
            return nil
        case 126:  // up arrow
            guard !state.results.isEmpty else { return nil }
            state.highlighted = (state.highlighted + state.results.count - 1)
                % state.results.count
            return nil
        case 125:  // down arrow
            guard !state.results.isEmpty else { return nil }
            state.highlighted = (state.highlighted + 1) % state.results.count
            return nil
        default:
            return event  // everything else types into the field
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    // MARK: SwiftUI content

    private struct SearchPaletteView: View {
        @ObservedObject var state: PaletteState
        let onQueryChange: (String) -> Void
        let onChoose: (Int) -> Void
        @FocusState private var fieldFocused: Bool

        private static let maxVisibleRows = 8

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find in Notes", text: $state.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .focused($fieldFocused)
                        .onChange(of: state.query) { _, query in
                            onQueryChange(query)
                        }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                if !state.results.isEmpty {
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(state.results.enumerated()),
                                        id: \.element.id) { index, match in
                                    ResultRow(match: match,
                                              highlighted: index == state.highlighted)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onChoose(index) }
                                        .onHover { hovering in
                                            if hovering { state.highlighted = index }
                                        }
                                }
                            }
                            .padding(6)
                        }
                        .frame(height: listHeight)
                        .onChange(of: state.highlighted) { _, index in
                            proxy.scrollTo(index)
                        }
                    }
                } else if !state.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Divider()
                    Text("No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(height: 36)
                }
            }
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .onAppear {
                // The panel becomes key asynchronously; focus after that.
                DispatchQueue.main.async { fieldFocused = true }
            }
        }

        private var listHeight: CGFloat {
            let rows = min(state.results.count, Self.maxVisibleRows)
            return CGFloat(rows) * 46 + 12
        }
    }

    private struct ResultRow: View {
        let match: NoteSearch.Match
        let highlighted: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(match.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !match.isTitleMatch {
                    Text(match.snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(highlighted ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(highlighted ? Color.accentColor.opacity(0.25) : .clear))
        }
    }
}
