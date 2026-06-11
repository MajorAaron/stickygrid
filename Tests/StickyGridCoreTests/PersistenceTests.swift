import Foundation
import Testing
@testable import StickyGridCore

@Suite("Notes document persistence")
struct PersistenceTests {

    private func sampleDocument() -> NotesDocument {
        NotesDocument(notes: [
            NoteRecord(
                frame: CGRect(x: 100, y: 200, width: 320, height: 240),
                colorID: .pink,
                fontName: "Avenir Next",
                fontSize: 16,
                pinned: true,
                zOrder: 1,
                titleSnippet: "Groceries"
            ),
            NoteRecord(
                frame: CGRect(x: 500, y: 300, width: 280, height: 200),
                colorID: .blue,
                zOrder: 0,
                titleSnippet: ""
            ),
        ])
    }

    @Test("encode/decode round-trips exactly")
    func roundTrip() throws {
        let original = sampleDocument()
        let decoded = try NotesDocument.decode(from: original.encode())
        #expect(decoded == original)
    }

    @Test("garbage data throws instead of crashing")
    func corruptData() {
        let garbage = Data("not json at all {{{".utf8)
        #expect(throws: (any Error).self) {
            try NotesDocument.decode(from: garbage)
        }
    }

    @Test("valid JSON with the wrong shape throws")
    func wrongShape() {
        let wrong = Data(#"{"version": "one", "notes": 7}"#.utf8)
        #expect(throws: (any Error).self) {
            try NotesDocument.decode(from: wrong)
        }
    }

    @Test("unknown extra fields are tolerated for forward compatibility")
    func unknownFields() throws {
        let doc = sampleDocument()
        var json = try JSONSerialization.jsonObject(with: doc.encode()) as! [String: Any]
        json["futureFeature"] = ["enabled": true]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try NotesDocument.decode(from: data)
        #expect(decoded == doc)
    }

    @Test("version field survives the round trip")
    func versionPreserved() throws {
        let doc = NotesDocument(version: 1, notes: [])
        let decoded = try NotesDocument.decode(from: doc.encode())
        #expect(decoded.version == 1)
    }

    @Test("every note color round-trips")
    func allColorsCodable() throws {
        for color in NoteColor.allCases {
            let doc = NotesDocument(notes: [
                NoteRecord(frame: .init(x: 0, y: 0, width: 100, height: 100), colorID: color)
            ])
            let decoded = try NotesDocument.decode(from: doc.encode())
            #expect(decoded.notes[0].colorID == color)
        }
    }
}
