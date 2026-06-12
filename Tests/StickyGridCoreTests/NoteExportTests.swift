import Foundation
import Testing
@testable import StickyGridCore

@Suite("sticky export filename planning")
struct NoteExportTests {

    private func record(
        _ uuid: String, title: String = "", pinned: Bool = false, zOrder: Int = 0
    ) -> NoteRecord {
        NoteRecord(id: UUID(uuidString: uuid)!,
                   frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                   pinned: pinned, zOrder: zOrder, titleSnippet: title)
    }

    @Test("entries keep the list order: pinned first, then frontmost")
    func ordering() {
        let back = record("AAAAAAAA-0000-0000-0000-000000000000", title: "back", zOrder: 2)
        let front = record("BBBBBBBB-0000-0000-0000-000000000000", title: "front", zOrder: 0)
        let pinned = record("CCCCCCCC-0000-0000-0000-000000000000", title: "pinned",
                            pinned: true, zOrder: 5)
        let names = NoteExport.entries(for: [back, front, pinned]).map(\.filename)
        #expect(names == ["pinned.md", "front.md", "back.md"])
    }

    @Test("slashes and colons become dashes, whitespace runs collapse")
    func sanitization() {
        let note = record("AAAAAAAA-0000-0000-0000-000000000000",
                          title: "Plan: Q3/Q4   review")
        #expect(NoteExport.entries(for: [note]).map(\.filename)
                == ["Plan- Q3-Q4 review.md"])
    }

    @Test("untitled notes fall back to Untitled, never a dotfile")
    func untitledFallback() {
        let empty = record("AAAAAAAA-0000-0000-0000-000000000000")
        let dotty = record("BBBBBBBB-0000-0000-0000-000000000000", title: "...")
        #expect(NoteExport.entries(for: [empty, dotty]).map(\.filename)
                == ["Untitled.md", "Untitled-bbbbbbbb.md"])
    }

    @Test("long titles are capped at 60 characters before the extension")
    func truncation() {
        let long = record("AAAAAAAA-0000-0000-0000-000000000000",
                          title: String(repeating: "x", count: 80))
        let name = NoteExport.entries(for: [long])[0].filename
        #expect(name == String(repeating: "x", count: 60) + ".md")
    }

    @Test("title collisions get an id8 suffix, case-insensitively")
    func collisions() {
        let first = record("AAAAAAAA-0000-0000-0000-000000000000",
                           title: "Groceries", zOrder: 0)
        let second = record("BBBBBBBB-0000-0000-0000-000000000000",
                            title: "groceries", zOrder: 1)
        #expect(NoteExport.entries(for: [first, second]).map(\.filename)
                == ["Groceries.md", "groceries-bbbbbbbb.md"])
    }

    @Test("entries carry the note id so the CLI can find the RTF")
    func carriesID() {
        let note = record("AAAAAAAA-0000-0000-0000-000000000000", title: "x")
        #expect(NoteExport.entries(for: [note])[0].id == note.id)
    }
}
