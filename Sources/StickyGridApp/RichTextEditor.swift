import AppKit
import StickyGridCore
import SwiftUI

/// TextKit 1 NSTextView wrapped for SwiftUI.
struct RichTextEditor: NSViewRepresentable {
    let viewModel: NoteViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Manual TextKit 1 stack: NSTextView(usingTextLayoutManager: false)
        // — scrollableTextView() would hand back TextKit 2, which still has
        // RTF/list edge cases.
        let textView = StickyTextView(usingTextLayoutManager: false)
        textView.isRichText = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.onDropMarkdownFiles = { [weak viewModel] in
            viewModel?.onImportFiles($0)
        }

        let font = NSFont(name: viewModel.fontName, size: viewModel.fontSize)
            ?? NSFont.systemFont(ofSize: viewModel.fontSize)
        let color = NSColor(viewModel.ink.resolved(on: viewModel.colorID))
        textView.font = font
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes = [.font: font, .foregroundColor: color]
        textView.bodyFont = font  // didSet restyles: empty notes start in header style

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        viewModel.textController.textView = textView
        if !viewModel.initialRTF.isEmpty {
            viewModel.textController.loadRTF(viewModel.initialRTF)
            viewModel.initialRTF = Data()
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Content flows AppKit → model; SwiftUI re-renders must not reset it.
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let viewModel: NoteViewModel
        init(viewModel: NoteViewModel) { self.viewModel = viewModel }

        func textDidChange(_ notification: Notification) {
            viewModel.onTextChanged()
        }

        /// stickygrid://open links raise their note in-process — no
        /// LaunchServices round-trip, so dev builds work too. Everything
        /// else returns false and gets NSTextView's default browser open.
        func textView(_ textView: NSTextView, clickedOnLink link: Any,
                      at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url, let open = OpenRequest.from(url: url) else { return false }
            viewModel.onOpenNoteLink(open.query)
            return true
        }
    }
}
