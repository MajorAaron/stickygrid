import Foundation
import Testing
@testable import StickyGridCore

@Suite("Capture URL builder (inverse of CaptureRequest.from(url:))")
struct CaptureURLTests {

    @Test("body only round-trips")
    func bodyRoundTrips() throws {
        let url = CaptureRequest.captureURL(body: "Buy milk", title: nil, color: nil)
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text == "Buy milk")
        #expect(request.color == nil)
        #expect(!request.hasExplicitTitle)
    }

    @Test("title, body, and color all survive the round trip")
    func fullRoundTrip() throws {
        let url = CaptureRequest.captureURL(body: "milk\neggs", title: "Groceries", color: .pink)
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text == "Groceries\nmilk\neggs")
        #expect(request.color == .pink)
        #expect(request.hasExplicitTitle)
    }

    @Test("query metacharacters and unicode are encoded, not mangled")
    func encodingEdges() throws {
        let body = "a&b=c?d#e\n50% off — café ☕️"
        let url = CaptureRequest.captureURL(body: body, title: "tom & jerry", color: nil)
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text == "tom & jerry\n" + body)
    }

    @Test("nil everything builds the bare empty-note URL")
    func bareURL() throws {
        let url = CaptureRequest.captureURL(body: nil, title: nil, color: nil)
        #expect(url.absoluteString == "stickygrid://new")
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text.isEmpty)
        #expect(!request.hasExplicitTitle)
    }

    @Test("empty strings are treated like nil")
    func emptyStringsOmitted() throws {
        let url = CaptureRequest.captureURL(body: "", title: "", color: nil)
        #expect(url.absoluteString == "stickygrid://new")
    }

    @Test("title alone round-trips with hasExplicitTitle")
    func titleOnly() throws {
        let url = CaptureRequest.captureURL(body: nil, title: "Call mom", color: nil)
        let request = try #require(CaptureRequest.from(url: url))
        #expect(request.text == "Call mom")
        #expect(request.hasExplicitTitle)
    }
}
