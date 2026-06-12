import Foundation
import Testing
@testable import StickyGridApp
@testable import StickyGridCore

@Suite("File → Export All Notes")
@MainActor
struct ExportAllNotesTests {

    private func record(
        _ uuid: String, title: String = "", pinned: Bool = false, zOrder: Int = 0
    ) -> NoteRecord {
        NoteRecord(id: UUID(uuidString: uuid)!,
                   frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                   pinned: pinned, zOrder: zOrder, titleSnippet: title)
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("export-all-tests-\(UUID().uuidString)")
    }

    @Test("writes one markdown file per note, NoteExport names, trailing newline")
    func writesEveryNote() throws {
        let groceries = record("AAAAAAAA-0000-0000-0000-000000000000",
                               title: "Groceries", zOrder: 0)
        let plan = record("BBBBBBBB-0000-0000-0000-000000000000",
                          title: "Plan", zOrder: 1)
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bodies = [groceries.id: "# Groceries\n\n- milk", plan.id: "# Plan"]
        let result = try WindowManager.exportAllNotes(
            records: [groceries, plan], markdown: { bodies[$0] }, to: directory)

        #expect(result == WindowManager.BulkExportResult(exported: 2, skipped: 0))
        #expect(try String(contentsOf: directory.appendingPathComponent("Groceries.md"),
                           encoding: .utf8) == "# Groceries\n\n- milk\n")
        #expect(try String(contentsOf: directory.appendingPathComponent("Plan.md"),
                           encoding: .utf8) == "# Plan\n")
    }

    @Test("empty notes are skipped, not written")
    func skipsEmptyNotes() throws {
        let titled = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Real")
        let empty = record("BBBBBBBB-0000-0000-0000-000000000000")
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try WindowManager.exportAllNotes(
            records: [titled, empty],
            markdown: { $0 == titled.id ? "body" : nil },
            to: directory)

        #expect(result == WindowManager.BulkExportResult(exported: 1, skipped: 1))
        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(written == ["Real.md"])
    }

    @Test("creates the destination directory when missing")
    func createsDirectory() throws {
        let directory = tempDirectory().appendingPathComponent("nested/vault")
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Hi")

        _ = try WindowManager.exportAllNotes(
            records: [note], markdown: { _ in "hi" }, to: directory)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path,
                                               isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("re-export overwrites stale files in place")
    func overwritesStaleContent() throws {
        let note = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Plan")
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try WindowManager.exportAllNotes(
            records: [note], markdown: { _ in "old" }, to: directory)
        _ = try WindowManager.exportAllNotes(
            records: [note], markdown: { _ in "new" }, to: directory)

        #expect(try String(contentsOf: directory.appendingPathComponent("Plan.md"),
                           encoding: .utf8) == "new\n")
    }
}
