import Foundation
import Testing
@testable import StickyGridCore

@Suite("sticky list/cat note listing")
struct NoteListingTests {

    private func record(
        _ uuid: String, title: String = "", pinned: Bool = false,
        zOrder: Int = 0, color: NoteColor = .yellow
    ) -> NoteRecord {
        NoteRecord(id: UUID(uuidString: uuid)!,
                   frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                   colorID: color, pinned: pinned, zOrder: zOrder,
                   titleSnippet: title)
    }

    @Test("pinned notes sort first, then frontmost (low zOrder)")
    func sortOrder() {
        let a = record("AAAAAAAA-0000-0000-0000-000000000000", title: "back", zOrder: 2)
        let b = record("BBBBBBBB-0000-0000-0000-000000000000", title: "front", zOrder: 0)
        let c = record("CCCCCCCC-0000-0000-0000-000000000000", title: "pinned", pinned: true, zOrder: 5)
        let lines = NoteListing.lines(for: [a, b, c])
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("cccccccc"))
        #expect(lines[1].hasPrefix("bbbbbbbb"))
        #expect(lines[2].hasPrefix("aaaaaaaa"))
    }

    @Test("line format: id8, pin column, padded title, bracketed color")
    func lineFormat() {
        let pinned = record("AAAAAAAA-0000-0000-0000-000000000000",
                            title: "Groceries", pinned: true, color: .pink)
        let untitled = record("BBBBBBBB-0000-0000-0000-000000000000", color: .blue)
        #expect(NoteListing.lines(for: [pinned, untitled]) == [
            "aaaaaaaa  * Groceries          [pink]",
            "bbbbbbbb    Untitled           [blue]",
        ])
    }

    @Test("long titles push the color right rather than truncate")
    func longTitle() {
        let r = record("AAAAAAAA-0000-0000-0000-000000000000",
                       title: "A very long title that keeps going")
        #expect(NoteListing.lines(for: [r])
                == ["aaaaaaaa    A very long title that keeps going [yellow]"])
    }

    @Test("query matches a case-insensitive id prefix, hyphens ignored")
    func idPrefixMatch() {
        let r = record("AB12CD34-0000-0000-0000-000000000000", title: "x")
        #expect(NoteListing.match("ab12cd", in: [r]) == .one(r))
        #expect(NoteListing.match("AB12CD340000", in: [r]) == .one(r))
    }

    @Test("query matches a case-insensitive title substring")
    func titleMatch() {
        let r = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Release Notes")
        #expect(NoteListing.match("release", in: [r]) == .one(r))
        #expect(NoteListing.match("NOTES", in: [r]) == .one(r))
    }

    @Test("no hit and ambiguous hits are distinct results")
    func noneAndMany() {
        let a = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Notes one")
        let b = record("BBBBBBBB-0000-0000-0000-000000000000", title: "Notes two")
        #expect(NoteListing.match("zzz", in: [a, b]) == .none)
        #expect(NoteListing.match("notes", in: [a, b]) == .many([a, b]))
    }

    @Test("STICKYGRID_DIR overrides the Application Support default")
    func directoryResolution() {
        let home = URL(fileURLWithPath: "/Users/zoe")
        #expect(NoteListing.storeDirectory(environment: [:], home: home).path
                == "/Users/zoe/Library/Application Support/StickyGrid")
        #expect(NoteListing.storeDirectory(
                    environment: ["STICKYGRID_DIR": "/tmp/sg"], home: home).path
                == "/tmp/sg")
    }
}
