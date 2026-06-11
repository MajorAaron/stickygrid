import Foundation
import Testing
@testable import StickyGridCore

@Suite("Capture requests (URL scheme, services, clipboard)")
struct CaptureRequestTests {

    // MARK: stickygrid:// URLs

    @Test("parses text from stickygrid://new")
    func parsesText() throws {
        let url = try #require(URL(string: "stickygrid://new?text=Buy%20milk"))
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text == "Buy milk")
        #expect(request.color == nil)
    }

    @Test("title becomes the first line above the body")
    func titlePrependedToBody() throws {
        let url = try #require(URL(string: "stickygrid://new?title=Groceries&text=milk%0Aeggs"))
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text == "Groceries\nmilk\neggs")
    }

    @Test("title alone is enough")
    func titleOnly() throws {
        let url = try #require(URL(string: "stickygrid://new?title=Call%20mom"))
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text == "Call mom")
    }

    @Test("color is parsed case-insensitively")
    func colorParsed() throws {
        let url = try #require(URL(string: "stickygrid://new?text=hi&color=Pink"))
        #expect(CaptureRequest.from(url: url)?.color == .pink)
    }

    @Test("unknown color is ignored, request still valid")
    func unknownColorIgnored() throws {
        let url = try #require(URL(string: "stickygrid://new?text=hi&color=chartreuse"))
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.color == nil)
        #expect(request.text == "hi")
    }

    @Test("bare stickygrid://new creates an empty note")
    func bareNewIsEmptyNote() throws {
        let url = try #require(URL(string: "stickygrid://new"))
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text.isEmpty)
    }

    @Test("path form stickygrid:///new also works")
    func pathForm() throws {
        let url = try #require(URL(string: "stickygrid:///new?text=hi"))
        #expect(CaptureRequest.from(url: url)?.text == "hi")
    }

    @Test("body is accepted as an alias for text")
    func bodyAlias() throws {
        let url = try #require(URL(string: "stickygrid://new?body=hi"))
        #expect(CaptureRequest.from(url: url)?.text == "hi")
    }

    @Test("wrong scheme is rejected")
    func wrongScheme() throws {
        let url = try #require(URL(string: "https://new?text=hi"))
        #expect(CaptureRequest.from(url: url) == nil)
    }

    @Test("unknown action is rejected")
    func unknownAction() throws {
        let url = try #require(URL(string: "stickygrid://delete?text=hi"))
        #expect(CaptureRequest.from(url: url) == nil)
    }

    // MARK: Plain text (Services menu, clipboard)

    @Test("plain text is trimmed of surrounding whitespace")
    func plainTextTrimmed() {
        let request = CaptureRequest.from(plainText: "  hello\n\n")
        #expect(request?.text == "hello")
    }

    @Test("interior newlines are preserved")
    func interiorNewlinesKept() {
        let request = CaptureRequest.from(plainText: "title\nbody\n")
        #expect(request?.text == "title\nbody")
    }

    @Test("empty or whitespace-only text is rejected")
    func emptyPlainTextRejected() {
        #expect(CaptureRequest.from(plainText: nil) == nil)
        #expect(CaptureRequest.from(plainText: "") == nil)
        #expect(CaptureRequest.from(plainText: "  \n\t") == nil)
    }

    @Test("first line drives the title snippet")
    func snippetFromFirstLine() {
        let request = CaptureRequest(text: "Groceries\nmilk")
        #expect(request.titleSnippet == "Groceries")
        let long = CaptureRequest(text: String(repeating: "x", count: 100))
        #expect(request.titleSnippet.count <= 40)
        #expect(long.titleSnippet.count == 40)
    }
}
