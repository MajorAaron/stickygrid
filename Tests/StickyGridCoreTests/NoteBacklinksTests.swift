import Foundation
import Testing
@testable import StickyGridCore

@Suite("Backlinks — which notes link to this one")
struct NoteBacklinksTests {

    private func record(
        _ uuid: String, title: String = "", pinned: Bool = false, zOrder: Int = 0
    ) -> NoteRecord {
        NoteRecord(id: UUID(uuidString: uuid)!,
                   frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                   colorID: .yellow, pinned: pinned, zOrder: zOrder,
                   titleSnippet: title)
    }

    private func link(_ record: NoteRecord) -> String {
        "stickygrid://open?note=\(record.id.uuidString.lowercased())"
    }

    let plan = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!

    // MARK: linkedIDs(in:records:)

    @Test("full-uuid open links resolve amid prose")
    func uuidLinks() {
        let target = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Trip Plan")
        let other = record("BBBBBBBB-0000-0000-0000-000000000000", title: "Packing")
        let text = "see \(link(target)) before you go, then \(link(other))."
        #expect(NoteBacklinks.linkedIDs(in: text, records: [target, other])
                == [target.id, other.id])
    }

    @Test("id-prefix and title queries resolve like deep links do")
    func queryLinks() {
        let target = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Trip Plan")
        let other = record("BBBBBBBB-0000-0000-0000-000000000000", title: "Packing")
        let text = """
        stickygrid://open?note=aaaaaaaa
        stickygrid://open?note=Packing
        """
        #expect(NoteBacklinks.linkedIDs(in: text, records: [target, other])
                == [target.id, other.id])
    }

    @Test("web links, capture links, and unknown ids resolve to nothing")
    func nonLinks() {
        let target = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Trip Plan")
        let text = """
        https://example.test/aaaaaaaa
        stickygrid://new?text=hello
        stickygrid://open?note=cccccccc-0000-0000-0000-000000000000
        """
        #expect(NoteBacklinks.linkedIDs(in: text, records: [target]).isEmpty)
    }

    // MARK: records(linkingTo:in:body:)

    @Test("backlinks come back in list order — pinned first, then frontmost")
    func listOrder() {
        let target = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Trip Plan")
        let back = record("BBBBBBBB-0000-0000-0000-000000000000", zOrder: 2)
        let front = record("CCCCCCCC-0000-0000-0000-000000000000", zOrder: 0)
        let pinned = record("DDDDDDDD-0000-0000-0000-000000000000", pinned: true, zOrder: 5)
        let records = [target, back, front, pinned]
        let bodies = Dictionary(uniqueKeysWithValues: records.map {
            ($0.id, "linking: \(link(target))")
        })
        let backlinks = NoteBacklinks.records(linkingTo: target.id, in: records) {
            bodies[$0]
        }
        #expect(backlinks.map(\.id) == [pinned.id, front.id, back.id])
    }

    @Test("a self-linking target is not its own backlink")
    func selfLink() {
        let target = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Trip Plan")
        let backlinks = NoteBacklinks.records(linkingTo: target.id, in: [target]) { _ in
            "me again: \(link(target))"
        }
        #expect(backlinks.isEmpty)
    }

    @Test("nil bodies and link-free notes are skipped; double links count once")
    func filtering() {
        let target = record("AAAAAAAA-0000-0000-0000-000000000000", title: "Trip Plan")
        let twice = record("BBBBBBBB-0000-0000-0000-000000000000")
        let empty = record("CCCCCCCC-0000-0000-0000-000000000000")
        let unrelated = record("DDDDDDDD-0000-0000-0000-000000000000")
        let records = [target, twice, empty, unrelated]
        let bodies: [UUID: String?] = [
            twice.id: "\(link(target)) and again \(link(target))",
            empty.id: nil,
            unrelated.id: "no links here, https://example.test only",
        ]
        let backlinks = NoteBacklinks.records(linkingTo: target.id, in: records) {
            bodies[$0] ?? nil
        }
        #expect(backlinks.map(\.id) == [twice.id])
    }
}
