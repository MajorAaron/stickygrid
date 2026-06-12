import AppKit
import StickyGridCore
import SwiftUI
import UniformTypeIdentifiers

/// Owns one NotePanel per note: creation, restoration, deletion, pinning,
/// frame tracking, and mosaic tiling.
final class WindowManager: NSObject, NSWindowDelegate, NSMenuDelegate {
    private let store: NoteStore
    private var panels: [UUID: NotePanel] = [:]
    private var viewModels: [UUID: NoteViewModel] = [:]

    init(store: NoteStore) {
        self.store = store
        super.init()
        store.rtfProvider = { [weak self] id in
            self?.viewModels[id]?.textController.rtfData()
        }
        store.zOrderProvider = { [weak self] in self?.currentZOrder() ?? [] }
    }

    // MARK: Lifecycle

    func restoreAll() {
        guard !store.records.isEmpty else {
            newNote(nil)
            return
        }
        // Back-most first so orderFront reproduces the stacking exactly.
        let backToFront = store.records.values.sorted { $0.zOrder > $1.zOrder }
        for record in backToFront {
            openWindow(for: record, focus: false)
        }
        if let front = backToFront.last, let panel = panels[front.id] {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc func newNote(_ sender: Any?) {
        let record = NoteRecord(frame: cascadeFrame())
        store.upsert(record)
        openWindow(for: record, focus: true)
    }

    /// Creates a note from outside the app (URL scheme, Services, clipboard,
    /// Quick Capture). With `activate: false` the note appears without
    /// pulling focus from whatever app the user is in.
    func createNote(from request: CaptureRequest, activate: Bool = true) {
        var record = NoteRecord(frame: cascadeFrame())
        if let color = request.color { record.colorID = color }
        let content = Self.captureContent(for: request, record: record)
        record.titleSnippet = content.titleSnippet
        store.upsert(record)
        openWindow(for: record, focus: activate, initialRTF: content.rtf)
        if content.rtf != nil {
            // The text arrived pre-typed; mark it dirty so the RTF persists
            // even if the user never edits the note.
            store.markTextChanged(record.id, snippet: content.titleSnippet)
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Title first so the color model reads the final text; sequential
        // because both actions guard on aiBusy — concurrent, the second
        // would silently bail.
        let autoTitle = Self.shouldAutoTitle(request: request,
                                             enabled: Self.autoTitleCaptureEnabled,
                                             hasAPIKey: NoteAI.apiKey() != nil)
        let autoColor = Self.shouldAutoColor(request: request,
                                             enabled: Self.autoColorCaptureEnabled,
                                             hasAPIKey: NoteAI.apiKey() != nil)
        if autoTitle || autoColor {
            let id = record.id
            Task { @MainActor [weak self] in
                if autoTitle { await self?.performSuggestTitle(on: id, quietly: true) }
                if autoColor { await self?.performSuggestColor(on: id, quietly: true) }
            }
        }
    }

    @objc func newNoteFromClipboard(_ sender: Any?) {
        guard let request = CaptureRequest.from(
            plainText: NSPasteboard.general.string(forType: .string)) else {
            NSSound.beep()
            return
        }
        createNote(from: request)
    }

    private func openWindow(for record: NoteRecord, focus: Bool, initialRTF: Data? = nil) {
        var record = record
        record.frame = rescueFrameIfOffScreen(record.frame)

        let viewModel = NoteViewModel(record: record)
        viewModel.initialRTF = store.loadRTF(for: record.id)
        if let initialRTF, viewModel.initialRTF.isEmpty {
            viewModel.initialRTF = initialRTF
        }
        let id = record.id
        viewModel.onNewNote = { [weak self] in self?.newNote(nil) }
        viewModel.onDelete = { [weak self] in self?.requestDelete(id) }
        viewModel.onTile = { [weak self] in self?.arrangeNotes(nil) }
        viewModel.onAppearanceChanged = { [weak self] in self?.appearanceChanged(id) }
        viewModel.onTextChanged = { [weak self] in self?.textChanged(id) }
        viewModel.onAIAction = { [weak self] action in self?.runAI(action, on: id) }
        viewModel.onAskAI = { [weak self] in self?.promptAskAI(on: id) }
        viewModel.onSuggestColor = { [weak self] in self?.suggestColor(on: id) }
        viewModel.onSuggestTitle = { [weak self] in self?.suggestTitle(on: id) }
        viewModel.onShare = { [weak self] in self?.shareNote(id) }
        viewModel.onImportFiles = { [weak self] urls in
            guard let self else { return }
            let imported = urls.filter { self.importNote(from: $0) }
            if imported.isEmpty { NSSound.beep() }
        }

        let panel = NotePanel(frame: record.frame)
        let container = NoteContainerView(color: record.colorID)
        let hosting = DraggableHostingView(NoteContentView(viewModel: viewModel))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container
        panel.delegate = self
        panel.level = record.pinned ? .floating : .normal

        panels[id] = panel
        viewModels[id] = viewModel

        if focus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    // MARK: Deletion (close = delete, like Stickies)

    @objc func deleteFrontNote(_ sender: Any?) {
        guard let id = noteID(of: NSApp.keyWindow) else { NSSound.beep(); return }
        requestDelete(id)
    }

    func requestDelete(_ id: UUID) {
        guard let panel = panels[id], let viewModel = viewModels[id] else { return }
        let text = viewModel.textController.plainText()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            deleteNote(id)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "Its text will be removed permanently."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: panel) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.deleteNote(id)
            }
        }
    }

    private func deleteNote(_ id: UUID) {
        if let panel = panels[id] {
            panel.delegate = nil
            panel.orderOut(nil)
        }
        panels[id] = nil
        viewModels[id] = nil
        store.remove(id)
    }

    // MARK: Note state changes

    private func appearanceChanged(_ id: UUID) {
        guard var record = store.records[id],
              let viewModel = viewModels[id],
              let panel = panels[id] else { return }

        if record.colorID != viewModel.colorID {
            (panel.contentView as? NoteContainerView)?.setColor(viewModel.colorID)
        }
        if record.colorID != viewModel.colorID || record.ink != viewModel.ink {
            viewModel.textController.applyTextColor(
                viewModel.ink.resolved(on: viewModel.colorID))
        }
        if record.fontName != viewModel.fontName || record.fontSize != viewModel.fontSize {
            viewModel.textController.applyFont(
                family: viewModel.fontName, size: viewModel.fontSize)
        }
        panel.level = viewModel.pinned ? .floating : .normal

        record.colorID = viewModel.colorID
        record.ink = viewModel.ink
        record.fontName = viewModel.fontName
        record.fontSize = viewModel.fontSize
        record.pinned = viewModel.pinned
        store.upsert(record)
    }

    private func textChanged(_ id: UUID) {
        guard let viewModel = viewModels[id] else { return }
        let firstLine = viewModel.textController.plainText()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        store.markTextChanged(id, snippet: String(firstLine.prefix(40)))
    }

    // MARK: Share & export

    @objc func shareFrontNote(_ sender: Any?) {
        guard let id = noteID(of: NSApp.keyWindow) else { NSSound.beep(); return }
        shareNote(id)
    }

    @objc func copyFrontNoteAsMarkdown(_ sender: Any?) {
        guard let markdown = frontNoteMarkdown() else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }

    @objc func exportFrontNoteAsMarkdown(_ sender: Any?) {
        guard let id = noteID(of: NSApp.keyWindow),
              let panel = panels[id],
              let markdown = noteMarkdown(id) else { NSSound.beep(); return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        savePanel.allowsOtherFileTypes = true
        savePanel.nameFieldStringValue = Self.exportFileName(
            title: viewModels[id]?.textController.plainText() ?? "")
        savePanel.beginSheetModal(for: panel) { response in
            guard response == .OK, let url = savePanel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    struct BulkExportResult: Equatable {
        var exported: Int
        var skipped: Int
    }

    /// File → Export All Notes…: the GUI twin of `sticky export` — every
    /// note becomes one .md file in a chosen folder, names via NoteExport
    /// so both surfaces write identical folders.
    @objc func exportAllNotesAsMarkdown(_ sender: Any?) {
        let records = Array(store.records.values)
        guard !records.isEmpty else { NSSound.beep(); return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Every note becomes one markdown file in this folder."
        panel.begin { [weak self] response in
            guard response == .OK, let self, let directory = panel.url else { return }
            do {
                let result = try Self.exportAllNotes(
                    records: records,
                    markdown: { self.noteMarkdown($0) },
                    to: directory)
                let alert = NSAlert()
                alert.messageText = "Exported \(result.exported) "
                    + (result.exported == 1 ? "note" : "notes")
                alert.informativeText = result.skipped > 0
                    ? "\(result.skipped) empty "
                      + (result.skipped == 1 ? "note was" : "notes were")
                      + " skipped."
                    : "Saved to \(directory.lastPathComponent)."
                alert.addButton(withTitle: "Show in Finder")
                alert.addButton(withTitle: "OK")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Writes one `<filename>.md` per note into `directory` (created if
    /// missing), overwriting stale files. Notes whose markdown is nil
    /// (empty notes) are skipped and counted.
    nonisolated static func exportAllNotes(
        records: [NoteRecord],
        markdown: (UUID) -> String?,
        to directory: URL
    ) throws -> BulkExportResult {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        var result = BulkExportResult(exported: 0, skipped: 0)
        for entry in NoteExport.entries(for: records) {
            guard let body = markdown(entry.id) else {
                result.skipped += 1
                continue
            }
            try (body + "\n").write(
                to: directory.appendingPathComponent(entry.filename),
                atomically: true, encoding: .utf8)
            result.exported += 1
        }
        return result
    }

    private func shareNote(_ id: UUID) {
        guard let panel = panels[id], let contentView = panel.contentView,
              let markdown = noteMarkdown(id) else { NSSound.beep(); return }
        panel.makeKeyAndOrderFront(nil)
        let picker = NSSharingServicePicker(items: [markdown])
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }

    private func frontNoteMarkdown() -> String? {
        noteID(of: NSApp.keyWindow).flatMap(noteMarkdown)
    }

    /// The note's markdown, or nil when the note is empty.
    private func noteMarkdown(_ id: UUID) -> String? {
        guard let markdown = viewModels[id]?.textController.markdownText(),
              !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return markdown
    }

    /// `<first line>.md`, sanitized for the filesystem.
    nonisolated static func exportFileName(title: String) -> String {
        let firstLine = title
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        let sanitized = firstLine
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
            .prefix(60)
        return (sanitized.isEmpty ? "Note" : String(sanitized)) + ".md"
    }

    // MARK: Markdown file import

    /// File → Import Markdown…: every chosen file becomes one styled note.
    @objc func importMarkdownFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText,
                                     UTType(filenameExtension: "markdown") ?? .plainText,
                                     .plainText]
        panel.message = "Each markdown file becomes a new sticky note."
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let imported = panel.urls.filter { self.importNote(from: $0) }
            if imported.isEmpty { NSSound.beep() }
        }
    }

    /// Creates one note from a markdown file; false when the file is
    /// unreadable or blank.
    @discardableResult
    func importNote(from url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        let record = NoteRecord(frame: cascadeFrame())
        guard let note = Self.importedNote(fromMarkdown: content, record: record)
        else { return false }
        var titled = record
        titled.titleSnippet = note.titleSnippet
        store.upsert(titled)
        openWindow(for: titled, focus: true, initialRTF: note.rtf)
        // The text arrived pre-typed; mark it dirty so the RTF persists even
        // if the user never edits the note.
        store.markTextChanged(titled.id, snippet: note.titleSnippet)
        return true
    }

    /// A markdown file's content rendered for a new note: RTF in the
    /// record's font and ink, plus the title snippet. Nil when the content
    /// is blank. A scratch editor (never shown) runs the same conversion as
    /// markdown paste, so marker literals, fonts, and list indentation match
    /// typed and pasted notes exactly.
    static func importedNote(
        fromMarkdown markdown: String, record: NoteRecord
    ) -> (rtf: Data, titleSnippet: String)? {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let scratch = StickyTextView(usingTextLayoutManager: false)
        scratch.isRichText = true
        let font = NSFont(name: record.fontName, size: record.fontSize)
            ?? .systemFont(ofSize: record.fontSize)
        scratch.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor(record.ink.resolved(on: record.colorID)),
        ]
        scratch.bodyFont = font
        scratch.insertMarkdown(markdown)

        guard let storage = scratch.textStorage, storage.length > 0,
              let rtf = storage.rtf(
                  from: NSRange(location: 0, length: storage.length),
                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        else { return nil }
        let title = scratch.string
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        return (rtf, String(title.prefix(40)))
    }

    /// A capture request rendered for its new note: markdown requests go
    /// through the same scratch-editor conversion as file import (snippet
    /// from the rendered text, so `# Heading` lists as `Heading`); plain
    /// requests keep today's verbatim RTF. Nil RTF means an empty note.
    static func captureContent(
        for request: CaptureRequest, record: NoteRecord
    ) -> (rtf: Data?, titleSnippet: String) {
        if request.markdown,
           let note = importedNote(fromMarkdown: request.text, record: record) {
            return (note.rtf, note.titleSnippet)
        }
        return (request.text.isEmpty ? nil : rtf(from: request.text, record: record),
                request.titleSnippet)
    }

    // MARK: AI Assist

    @objc func aiSummarizeNote(_ sender: Any?) { runAIOnFrontNote(.summarize) }
    @objc func aiChecklistNote(_ sender: Any?) { runAIOnFrontNote(.checklist) }
    @objc func aiPolishNote(_ sender: Any?) { runAIOnFrontNote(.polish) }

    @objc func aiAskNote(_ sender: Any?) {
        guard let id = noteID(of: NSApp.keyWindow) else { NSSound.beep(); return }
        promptAskAI(on: id)
    }

    @objc func aiSuggestColorNote(_ sender: Any?) {
        guard let id = noteID(of: NSApp.keyWindow) else { NSSound.beep(); return }
        suggestColor(on: id)
    }

    @objc func aiSuggestTitleNote(_ sender: Any?) {
        guard let id = noteID(of: NSApp.keyWindow) else { NSSound.beep(); return }
        suggestTitle(on: id)
    }

    /// Like suggestColor, but the result is inserted as a new first line —
    /// the old text shifts down intact, and one undo reverts it.
    private func suggestTitle(on id: UUID, quietly: Bool = false) {
        Task { @MainActor [weak self] in
            await self?.performSuggestTitle(on: id, quietly: quietly)
        }
    }

    /// The quiet path (auto-title on capture) never beeps, prompts, or
    /// alerts — its preconditions were checked by `shouldAutoTitle`, and a
    /// failed capture titling just leaves the note as it is.
    private func performSuggestTitle(on id: UUID, quietly: Bool) async {
        guard let viewModel = viewModels[id], !viewModel.aiBusy else { return }
        let text = viewModel.textController.plainText()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if !quietly { NSSound.beep() }
            return
        }
        guard NoteAI.apiKey() != nil else {
            if !quietly { promptForAPIKey() }
            return
        }

        viewModel.aiBusy = true
        defer { viewModel.aiBusy = false }
        do {
            let title = try await NoteAI.suggestTitle(for: text)
            viewModel.textController.insertTitleLine(title)
        } catch {
            if !quietly { presentAIError(error, on: id) }
        }
    }

    // MARK: Auto-color / auto-title on capture

    private nonisolated static let autoColorCaptureKey = "AIAutoColorCapture"

    /// Off by default: auto-color spends API tokens on every capture.
    nonisolated static var autoColorCaptureEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoColorCaptureKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoColorCaptureKey) }
    }

    /// Whether a captured note should quietly color itself. Capture must
    /// never prompt, so a missing key disables it; an explicit color in the
    /// request means the caller already chose.
    nonisolated static func shouldAutoColor(
        request: CaptureRequest, enabled: Bool, hasAPIKey: Bool
    ) -> Bool {
        enabled && hasAPIKey && request.color == nil
            && !request.text
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc func toggleAutoColorCapture(_ sender: Any?) {
        Self.autoColorCaptureEnabled.toggle()
    }

    private nonisolated static let autoTitleCaptureKey = "AIAutoTitleCapture"

    /// Off by default: auto-title spends API tokens on every capture.
    nonisolated static var autoTitleCaptureEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoTitleCaptureKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoTitleCaptureKey) }
    }

    /// Whether a captured note should quietly title itself. Capture must
    /// never prompt, so a missing key disables it; an explicit title in
    /// the request means the caller already chose.
    nonisolated static func shouldAutoTitle(
        request: CaptureRequest, enabled: Bool, hasAPIKey: Bool
    ) -> Bool {
        enabled && hasAPIKey && !request.hasExplicitTitle
            && !request.text
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc func toggleAutoTitleCapture(_ sender: Any?) {
        Self.autoTitleCaptureEnabled.toggle()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAutoColorCapture(_:)) {
            item.state = Self.autoColorCaptureEnabled ? .on : .off
        }
        if item.action == #selector(toggleAutoTitleCapture(_:)) {
            item.state = Self.autoTitleCaptureEnabled ? .on : .off
        }
        return true
    }

    /// Like runAI, but the result is a palette color instead of new text.
    private func suggestColor(on id: UUID, quietly: Bool = false) {
        Task { @MainActor [weak self] in
            await self?.performSuggestColor(on: id, quietly: quietly)
        }
    }

    /// The quiet path (auto-color on capture) never beeps, prompts, or
    /// alerts — its preconditions were checked by `shouldAutoColor`, and a
    /// failed capture coloring just leaves the note as it is.
    private func performSuggestColor(on id: UUID, quietly: Bool) async {
        guard let viewModel = viewModels[id], !viewModel.aiBusy else { return }
        let text = viewModel.textController.plainText()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if !quietly { NSSound.beep() }
            return
        }
        guard NoteAI.apiKey() != nil else {
            if !quietly { promptForAPIKey() }
            return
        }

        viewModel.aiBusy = true
        defer { viewModel.aiBusy = false }
        do {
            viewModel.colorID = try await NoteAI.suggestColor(for: text)
            appearanceChanged(id)
        } catch {
            if !quietly { presentAIError(error, on: id) }
        }
    }

    private static let lastAskInstructionKey = "AILastAskInstruction"

    /// Asks for a free-form instruction, then runs it on the note like a preset.
    private func promptAskAI(on id: UUID) {
        guard let viewModel = viewModels[id], !viewModel.aiBusy else { return }

        let alert = NSAlert()
        alert.messageText = "Ask AI"
        alert.informativeText =
            "Tell the AI what to do with this note — e.g. “translate to "
            + "Spanish” or “expand each bullet into a sentence”. The note's "
            + "text is replaced with the result."
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "What should the AI do with this note?"
        field.stringValue = UserDefaults.standard
            .string(forKey: Self.lastAskInstructionKey) ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let run = { [weak self] (response: NSApplication.ModalResponse) in
            guard response == .alertFirstButtonReturn else { return }
            let instruction = field.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty else { return }
            UserDefaults.standard.set(instruction, forKey: Self.lastAskInstructionKey)
            self?.runAI(.ask(instruction), on: id)
        }
        if let panel = panels[id] {
            alert.beginSheetModal(for: panel, completionHandler: run)
        } else {
            run(alert.runModal())
        }
    }

    private func runAIOnFrontNote(_ action: NoteAIAction) {
        guard let id = noteID(of: NSApp.keyWindow) else { NSSound.beep(); return }
        runAI(action, on: id)
    }

    private func runAI(_ action: NoteAIAction, on id: UUID) {
        guard let viewModel = viewModels[id], !viewModel.aiBusy else { return }
        let text = viewModel.textController.plainText()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { NSSound.beep(); return }
        guard NoteAI.apiKey() != nil else {
            promptForAPIKey()
            return
        }

        viewModel.aiBusy = true
        Task { @MainActor [weak self] in
            defer { viewModel.aiBusy = false }
            do {
                let result = try await NoteAI.transform(text, action: action)
                viewModel.textController.replaceAllText(with: result)
            } catch {
                self?.presentAIError(error, on: id)
            }
        }
    }

    private func presentAIError(_ error: Error, on id: UUID) {
        let alert = NSAlert()
        alert.messageText = "AI Assist failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if let panel = panels[id] {
            alert.beginSheetModal(for: panel)
        } else {
            alert.runModal()
        }
    }

    @objc func setAnthropicAPIKey(_ sender: Any?) {
        promptForAPIKey()
    }

    private func promptForAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Set Anthropic API Key"
        alert.informativeText = """
            AI Assist calls the Anthropic API directly. Paste an API key from \
            console.anthropic.com; it is stored locally in \
            ~/.config/stickygrid/anthropic-api-key (never synced). \
            The ANTHROPIC_API_KEY environment variable takes precedence.
            """
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "sk-ant-…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try NoteAI.saveKey(key)
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
        }
    }

    // MARK: Arranging

    private let layoutPalette = LayoutPaletteController()
    private static let lastLayoutKey = "lastUsedLayout"

    @objc func arrangeNotes(_ sender: Any?) {
        if layoutPalette.isVisible {
            layoutPalette.applyHighlighted()
            return
        }
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        let last = UserDefaults.standard.string(forKey: Self.lastLayoutKey)
            .flatMap(NoteLayout.init(rawValue:)) ?? .mosaic
        layoutPalette.show(on: screen, highlighting: last) { [weak self] layout in
            UserDefaults.standard.set(layout.rawValue, forKey: Self.lastLayoutKey)
            self?.arrange(using: layout, on: screen)
        }
    }

    private func arrange(using layout: NoteLayout, on screen: NSScreen) {
        let onScreen = panels.filter { _, panel in
            let mid = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            return (panel.screen ?? NSScreen.main) == screen
                || screen.frame.contains(mid)
        }
        guard !onScreen.isEmpty else { return }

        let entries = onScreen.sorted { $0.value.frame.minX < $1.value.frame.minX }
        let sizes = entries.map { $0.value.frame.size }
        let bounds = screen.visibleFrame

        let rects: [CGRect]
        switch layout {
        case .mosaic:
            rects = Treemap.layout(
                weights: sizes.map { Double($0.width * $0.height) }, in: bounds)
        case .evenGrid:
            rects = GridLayouts.evenGrid(count: entries.count, in: bounds)
        case .columns:
            rects = GridLayouts.columns(sizes: sizes, in: bounds)
        case .shuffle:
            var rng = SystemRandomNumberGenerator()
            rects = GridLayouts.scatter(sizes: sizes, in: bounds, using: &rng)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (entry, rect) in zip(entries, rects) {
                entry.value.animator().setFrame(rect, display: true)
            }
        }
        for ((id, _), rect) in zip(entries, rects) {
            if var record = store.records[id] {
                record.frame = rect
                store.upsert(record)
            }
        }
    }

    // MARK: Quick Capture

    private let quickCapturePalette = QuickCaptureController()

    /// Summoned by the global hotkey (⌃⌥N) or File → Quick Capture. The
    /// palette floats over whatever app is active; the captured note is
    /// created without stealing focus from that app.
    @objc func quickCapture(_ sender: Any?) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let screen else { return }
        quickCapturePalette.show(on: screen) { [weak self] request in
            self?.createNote(from: request, activate: false)
        }
    }

    // MARK: Find in Notes

    private let searchPalette = SearchPaletteController()

    @objc func findInNotes(_ sender: Any?) {
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        searchPalette.show(
            on: screen,
            search: { [weak self] query in
                guard let self else { return [] }
                // Frontmost first so results mirror what the user sees.
                var ordered = self.currentZOrder()
                ordered += self.viewModels.keys.filter { !ordered.contains($0) }
                let sources = ordered.compactMap { id -> NoteSearch.Source? in
                    guard let viewModel = self.viewModels[id] else { return nil }
                    return NoteSearch.Source(
                        id: id, text: viewModel.textController.plainText())
                }
                return NoteSearch.search(query: query, in: sources)
            },
            onChoose: { [weak self] match in
                self?.reveal(match)
            })
    }

    private func reveal(_ match: NoteSearch.Match) {
        guard let panel = panels[match.noteID] else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewModels[match.noteID]?.textController.reveal(
            NSRange(location: match.matchLocation, length: match.matchLength))
    }

    // MARK: Notes menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let sorted = store.records.values.sorted {
            ($0.titleSnippet.isEmpty ? "Untitled" : $0.titleSnippet)
                .localizedCaseInsensitiveCompare(
                    $1.titleSnippet.isEmpty ? "Untitled" : $1.titleSnippet) == .orderedAscending
        }
        if sorted.isEmpty {
            let item = NSMenuItem(title: "No Notes", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }
        for record in sorted {
            let title = record.titleSnippet.isEmpty ? "Untitled" : record.titleSnippet
            let item = NSMenuItem(title: title, action: #selector(focusNote(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = record.id
            menu.addItem(item)
        }
    }

    @objc private func focusNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let panel = panels[id] else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Window delegate (frame tracking)

    func windowDidMove(_ notification: Notification) {
        persistFrame(of: notification.object as? NSWindow)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrame(of: notification.object as? NSWindow)
    }

    private func persistFrame(of window: NSWindow?) {
        guard let id = noteID(of: window), var record = store.records[id] else { return }
        record.frame = window!.frame
        store.upsert(record)
    }

    // MARK: Helpers

    /// Plain captured text styled with the note's font and ink, as RTF the
    /// editor loads like any persisted note (header restyle included).
    private static func rtf(from text: String, record: NoteRecord) -> Data {
        let font = NSFont(name: record.fontName, size: record.fontSize)
            ?? NSFont.systemFont(ofSize: record.fontSize)
        let color = NSColor(record.ink.resolved(on: record.colorID))
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color])
        return attributed.rtf(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            ?? Data()
    }

    private func noteID(of window: NSWindow?) -> UUID? {
        guard let window else { return nil }
        return panels.first { $0.value === window }?.key
    }

    private func currentZOrder() -> [UUID] {
        // Front-to-back; zOrder 0 = frontmost.
        NSApp.orderedWindows.compactMap { noteID(of: $0) }
    }

    private func cascadeFrame() -> NSRect {
        let size = NSSize(width: 320, height: 240)
        if let key = NSApp.keyWindow, noteID(of: key) != nil {
            let offset = key.frame.offsetBy(dx: 28, dy: -28)
            return rescueFrameIfOffScreen(
                NSRect(origin: offset.origin, size: size))
        }
        guard let screen = NSScreen.main else {
            return NSRect(x: 200, y: 200, width: size.width, height: size.height)
        }
        let visible = screen.visibleFrame
        let step = CGFloat(panels.count % 8) * 28
        return NSRect(
            x: visible.minX + visible.width * 0.35 + step,
            y: visible.maxY - 120 - size.height - step,
            width: size.width, height: size.height)
    }

    private func rescueFrameIfOffScreen(_ frame: CGRect) -> CGRect {
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame.intersection(frame)
            if !visible.isNull, visible.width >= 40, visible.height >= 40 {
                return frame
            }
        }
        guard let main = NSScreen.main else { return frame }
        let visible = main.visibleFrame
        let step = CGFloat(panels.count % 8) * 28
        return CGRect(
            x: visible.minX + 80 + step,
            y: visible.maxY - 80 - frame.height - step,
            width: min(frame.width, visible.width - 160),
            height: min(frame.height, visible.height - 160))
    }
}
