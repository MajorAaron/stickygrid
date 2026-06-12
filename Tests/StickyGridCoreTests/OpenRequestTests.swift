import Foundation
import Testing
@testable import StickyGridCore

@Suite("stickygrid://open deep-link parsing")
struct OpenRequestTests {

    @Test("note= query is parsed")
    func noteParam() throws {
        let url = URL(string: "stickygrid://open?note=release")!
        let request = try #require(OpenRequest.from(url: url))
        #expect(request.query == "release")
    }

    @Test("id= is an alias for note=")
    func idAlias() throws {
        let url = URL(string: "stickygrid://open?id=ab12cd34")!
        #expect(try #require(OpenRequest.from(url: url)).query == "ab12cd34")
    }

    @Test("percent-encoded queries decode")
    func percentDecoding() throws {
        let url = URL(string: "stickygrid://open?note=release%20notes%20%E2%98%95")!
        #expect(try #require(OpenRequest.from(url: url)).query == "release notes ☕")
    }

    @Test("scheme and host are case-insensitive")
    func caseInsensitive() throws {
        let url = URL(string: "STICKYGRID://Open?note=x")!
        #expect(OpenRequest.from(url: url) != nil)
    }

    @Test("missing or empty query is nil — nothing to open")
    func emptyQuery() {
        #expect(OpenRequest.from(url: URL(string: "stickygrid://open")!) == nil)
        #expect(OpenRequest.from(url: URL(string: "stickygrid://open?note=")!) == nil)
    }

    @Test("capture URLs are not open requests, and vice versa")
    func disjointFromCapture() {
        let capture = URL(string: "stickygrid://new?text=hi")!
        let open = URL(string: "stickygrid://open?note=hi")!
        #expect(OpenRequest.from(url: capture) == nil)
        #expect(CaptureRequest.from(url: open) == nil)
    }

    @Test("foreign schemes are nil")
    func foreignScheme() {
        #expect(OpenRequest.from(url: URL(string: "https://open?note=x")!) == nil)
    }

    @Test("openURL builder round-trips through from(url:)")
    func builderRoundTrips() throws {
        let query = "tom & jerry — café ☕️"
        let url = OpenRequest.openURL(query: query)
        #expect(url.scheme == "stickygrid")
        #expect(url.host == "open")
        #expect(try #require(OpenRequest.from(url: url)).query == query)
    }
}
