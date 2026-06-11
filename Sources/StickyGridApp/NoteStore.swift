import Foundation
import StickyGridCore

/// Owns the persisted state: notes.json + one <uuid>.rtf per note in
/// ~/Library/Application Support/StickyGrid/. Debounced autosave, atomic
/// writes with retry, and never-crash corruption recovery on load.
final class NoteStore {
    private(set) var records: [UUID: NoteRecord] = [:]
    private(set) var saveFailed = false

    private let directory: URL
    private var dirtyRTF: Set<UUID> = []
    private var metadataDirty = false
    private var saveTask: Task<Void, Never>?

    /// Supplies live RTF data for a note (wired to the open text views).
    var rtfProvider: (UUID) -> Data? = { _ in nil }
    /// Supplies the current back-to-front z-order of note IDs.
    var zOrderProvider: () -> [UUID] = { [] }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyGrid", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: Load

    private func load() {
        let url = directory.appendingPathComponent("notes.json")
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let document = try NotesDocument.decode(from: data)
            records = Dictionary(uniqueKeysWithValues: document.notes.map { ($0.id, $0) })
        } catch {
            backUpCorruptFile(at: url)
            records = [:]
        }
    }

    /// Returns the note's RTF data, backing up a corrupt file rather than failing.
    func loadRTF(for id: UUID) -> Data {
        let url = rtfURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return Data() }
        guard let data = try? Data(contentsOf: url) else {
            backUpCorruptFile(at: url)
            return Data()
        }
        return data
    }

    private func backUpCorruptFile(at url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = url.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: backup)
        NSLog("StickyGrid: backed up unreadable file to \(backup.lastPathComponent)")
    }

    // MARK: Mutations

    func upsert(_ record: NoteRecord) {
        records[record.id] = record
        metadataDirty = true
        scheduleSave()
    }

    func markTextChanged(_ id: UUID, snippet: String) {
        dirtyRTF.insert(id)
        if var record = records[id] {
            record.titleSnippet = snippet
            records[id] = record
        }
        metadataDirty = true
        scheduleSave()
    }

    func remove(_ id: UUID) {
        records[id] = nil
        dirtyRTF.remove(id)
        try? FileManager.default.removeItem(at: rtfURL(for: id))
        metadataDirty = true
        flushNow()
    }

    // MARK: Saving

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.performSave()
        }
    }

    /// Synchronous flush for close/quit paths.
    func flushNow() {
        saveTask?.cancel()
        saveTask = nil
        performSave()
    }

    private func performSave() {
        saveFailed = false

        for id in dirtyRTF {
            guard records[id] != nil, let data = rtfProvider(id) else { continue }
            if writeWithRetry(data, to: rtfURL(for: id)) {
                dirtyRTF.remove(id)
            } else {
                saveFailed = true
            }
        }

        guard metadataDirty else { return }
        var notes = Array(records.values)
        let order = zOrderProvider()
        if !order.isEmpty {
            let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            notes = notes.map { note in
                var note = note
                note.zOrder = index[note.id] ?? note.zOrder
                return note
            }
        }
        notes.sort { $0.zOrder < $1.zOrder }

        do {
            let data = try NotesDocument(notes: notes).encode()
            if writeWithRetry(data, to: directory.appendingPathComponent("notes.json")) {
                metadataDirty = false
            } else {
                saveFailed = true
            }
        } catch {
            saveFailed = true
            NSLog("StickyGrid: failed to encode notes.json: \(error)")
        }
    }

    private func writeWithRetry(_ data: Data, to url: URL) -> Bool {
        for (attempt, delay) in [0.0, 0.2, 0.5].enumerated() {
            if attempt > 0 { Thread.sleep(forTimeInterval: delay) }
            do {
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                NSLog("StickyGrid: save attempt \(attempt + 1) failed for \(url.lastPathComponent): \(error)")
            }
        }
        return false
    }

    private func rtfURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).rtf")
    }
}
