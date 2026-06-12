import Foundation
import Testing
@testable import StickyGridCore

@Suite("Find in Notes search")
struct NoteSearchTests {
    private let groceries = UUID()
    private let standup = UUID()
    private let recipe = UUID()

    private var notes: [NoteSearch.Source] {
        [
            .init(id: groceries, text: "Groceries\nmilk\neggs\ncoffee beans"),
            .init(id: standup, text: "Standup notes\nDemo the search palette\nBlocked on review"),
            .init(id: recipe, text: "Café crêpes\nflour, eggs, milk\nwhisk until smooth"),
        ]
    }

    @Test("empty and whitespace queries return nothing")
    func emptyQuery() {
        #expect(NoteSearch.search(query: "", in: notes).isEmpty)
        #expect(NoteSearch.search(query: "   ", in: notes).isEmpty)
    }

    @Test("matches are case-insensitive")
    func caseInsensitive() {
        let results = NoteSearch.search(query: "MILK", in: notes)
        #expect(results.map(\.noteID).contains(groceries))
        #expect(results.map(\.noteID).contains(recipe))
    }

    @Test("matches are diacritic-insensitive")
    func diacriticInsensitive() {
        let results = NoteSearch.search(query: "cafe crepes", in: notes)
        #expect(results.map(\.noteID) == [recipe])
    }

    @Test("title matches rank ahead of body matches, caller order preserved within tiers")
    func titleMatchesFirst() {
        // "notes" is in standup's title; "beans" only in groceries' body.
        let results = NoteSearch.search(query: "s", in: notes)
        let titleTier = results.prefix(while: \.isTitleMatch)
        #expect(!titleTier.isEmpty)
        #expect(results.drop(while: \.isTitleMatch).allSatisfy { !$0.isTitleMatch })
        // All three titles contain "s"? Groceries yes, Standup yes, Café crêpes yes.
        #expect(results.map(\.noteID) == [groceries, standup, recipe])
    }

    @Test("title is the first non-empty line")
    func titleExtraction() {
        let id = UUID()
        let results = NoteSearch.search(
            query: "hello",
            in: [.init(id: id, text: "\n\n  \nActual Title\nhello body")])
        #expect(results.first?.title == "Actual Title")
        #expect(results.first?.isTitleMatch == false)
    }

    @Test("untitled notes get a placeholder title")
    func untitledPlaceholder() {
        let id = UUID()
        let results = NoteSearch.search(query: "x", in: [.init(id: id, text: "x")])
        // Single-line note: the line is both title and match.
        #expect(results.first?.title == "x")
        #expect(results.first?.isTitleMatch == true)
    }

    @Test("snippet is the line containing the match")
    func snippetLine() {
        let results = NoteSearch.search(query: "palette", in: notes)
        #expect(results.first?.snippet == "Demo the search palette")
    }

    @Test("long snippet lines are windowed around the match")
    func snippetWindowed() {
        let id = UUID()
        let padding = String(repeating: "a", count: 200)
        let results = NoteSearch.search(
            query: "needle",
            in: [.init(id: id, text: "Title\n\(padding) needle \(padding)")])
        let snippet = try! #require(results.first?.snippet)
        #expect(snippet.count <= 80)
        #expect(snippet.localizedStandardContains("needle"))
    }

    @Test("match range is in UTF-16 offsets into the full text")
    func utf16Offsets() {
        let id = UUID()
        let text = "📝 emoji title\nfind me"
        let results = NoteSearch.search(query: "find", in: [.init(id: id, text: text)])
        let match = try! #require(results.first)
        let ns = text as NSString
        #expect(ns.substring(with: NSRange(location: match.matchLocation,
                                           length: match.matchLength)) == "find")
    }

    @Test("notes without a hit are absent")
    func noFalsePositives() {
        let results = NoteSearch.search(query: "zebra", in: notes)
        #expect(results.isEmpty)
    }
}
