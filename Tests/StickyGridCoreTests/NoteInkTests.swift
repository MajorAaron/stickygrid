import Foundation
import Testing
@testable import StickyGridCore

@Suite("Note ink (text color)")
struct NoteInkTests {

    @Test("auto resolves to the background's tuned foreground")
    func autoFollowsBackground() {
        for color in NoteColor.allCases {
            #expect(NoteInk.auto.resolved(on: color) == color.foreground)
        }
    }

    @Test("an override ink resolves to its own color on every background")
    func overrideIgnoresBackground() {
        for ink in NoteInk.allCases where ink != .auto {
            let onYellow = ink.resolved(on: .yellow)
            for color in NoteColor.allCases {
                #expect(ink.resolved(on: color) == onYellow,
                        "\(ink) should not vary by background")
            }
            #expect(onYellow != NoteColor.yellow.foreground,
                    "\(ink) should differ from the auto foreground")
        }
    }

    @Test("every ink round-trips through the document")
    func inkRoundTrips() throws {
        for ink in NoteInk.allCases {
            let doc = NotesDocument(notes: [
                NoteRecord(frame: .init(x: 0, y: 0, width: 100, height: 100), ink: ink)
            ])
            let decoded = try NotesDocument.decode(from: doc.encode())
            #expect(decoded.notes[0].ink == ink)
        }
    }

    @Test("records saved before the ink field decode as auto")
    func missingInkDecodesAsAuto() throws {
        let doc = NotesDocument(notes: [
            NoteRecord(frame: .init(x: 0, y: 0, width: 100, height: 100), ink: .red)
        ])
        var json = try JSONSerialization.jsonObject(with: doc.encode()) as! [String: Any]
        var notes = json["notes"] as! [[String: Any]]
        notes[0].removeValue(forKey: "ink")
        json["notes"] = notes
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try NotesDocument.decode(from: data)
        #expect(decoded.notes[0].ink == .auto)
    }
}
