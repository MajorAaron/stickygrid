import AppKit
import StickyGridCore

/// Markdown drag-and-drop: dropped .md files become new styled notes, and
/// dropped plain-text markdown converts to styled runs at the drop point —
/// the drag counterparts of File → Import Markdown… and markdown paste.
extension StickyTextView {

    enum DropAction: Equatable {
        case importFiles([URL])
        case insertMarkdown(String)
        case passthrough
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    /// Classifies a drag pasteboard the way the paste override classifies
    /// NSPasteboard.general: markdown files win over any accompanying text,
    /// rich-text drags and markdown-free text keep default drop behavior.
    static func dropAction(for pasteboard: NSPasteboard) -> DropAction {
        let urls = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let markdownFiles = urls.filter {
            markdownExtensions.contains($0.pathExtension.lowercased())
        }
        if !markdownFiles.isEmpty {
            return .importFiles(markdownFiles)
        }

        let types = pasteboard.types ?? []
        if urls.isEmpty, !types.contains(.rtf), !types.contains(.rtfd),
           let text = pasteboard.string(forType: .string),
           MarkdownImport.detectsMarkdown(text) {
            return .insertMarkdown(text)
        }
        return .passthrough
    }

    // MARK: Drop handling

    /// File URLs must be acceptable for the dragging callbacks to fire at
    /// all — the view never imports attachments (importsGraphics is false),
    /// so NSTextView would not register for them on its own.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        var types = super.acceptableDragTypes
        if !types.contains(.fileURL) { types.append(.fileURL) }
        return types
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if case .importFiles = Self.dropAction(for: sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if case .importFiles = Self.dropAction(for: sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if case .importFiles = Self.dropAction(for: sender.draggingPasteboard) {
            return true
        }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        switch Self.dropAction(for: sender.draggingPasteboard) {
        case .importFiles(let urls):
            guard let onDropMarkdownFiles else {
                return super.performDragOperation(sender)
            }
            onDropMarkdownFiles(urls)
            return true
        case .insertMarkdown(let text):
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(
                NSRange(location: characterIndexForInsertion(at: point), length: 0))
            insertMarkdown(text)
            return true
        case .passthrough:
            return super.performDragOperation(sender)
        }
    }
}
