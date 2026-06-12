import Foundation
import Testing
@testable import StickyGridCore

@Suite("Link detection")
struct LinkDetectionTests {

    @Test("finds a stickygrid URL with its exact range")
    func stickygridURL() {
        let text = "see stickygrid://open?note=plan today"
        let matches = LinkDetection.matches(in: text)
        #expect(matches.count == 1)
        #expect(matches[0].url == URL(string: "stickygrid://open?note=plan"))
        #expect(matches[0].range == (text as NSString).range(of: "stickygrid://open?note=plan"))
    }

    @Test("finds web URLs, case-insensitive on the scheme")
    func webURLs() {
        let matches = LinkDetection.matches(in: "HTTPS://Example.test and http://a.test/b?c=1")
        #expect(matches.count == 2)
        #expect(matches[0].url == URL(string: "HTTPS://Example.test"))
        #expect(matches[1].url == URL(string: "http://a.test/b?c=1"))
    }

    @Test("trims trailing punctuation and closers")
    func trailingPunctuation() {
        let text = "(see https://x.test). Or stickygrid://open?note=plan,"
        let matches = LinkDetection.matches(in: text)
        #expect(matches.map(\.url) == [URL(string: "https://x.test")!,
                                       URL(string: "stickygrid://open?note=plan")!])
    }

    @Test("ranges are UTF-16 offsets, correct past non-BMP characters")
    func utf16Ranges() {
        let text = "🗒️🗒️ https://x.test"
        let matches = LinkDetection.matches(in: text)
        #expect(matches.count == 1)
        #expect(matches[0].range == (text as NSString).range(of: "https://x.test"))
    }

    @Test("plain text, bare words, and other schemes yield nothing")
    func noMatches() {
        #expect(LinkDetection.matches(in: "no links here, just stickygrid talk").isEmpty)
        #expect(LinkDetection.matches(in: "mailto:a@b.test file:///tmp/x").isEmpty)
        #expect(LinkDetection.matches(in: "").isEmpty)
    }

    @Test("multiple links in one paragraph all match")
    func multiple() {
        let text = "stickygrid://open?note=a then https://b.test then stickygrid://open?note=c"
        #expect(LinkDetection.matches(in: text).count == 3)
    }
}
