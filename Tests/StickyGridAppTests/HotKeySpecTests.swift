import Carbon.HIToolbox
import Testing
@testable import StickyGridApp

@Suite("Quick Capture hotkey spec")
struct HotKeySpecTests {

    @Test("parses the default ctrl+alt+n combo")
    func defaultCombo() {
        let spec = HotKeySpec.parse("ctrl+alt+n")
        #expect(spec?.keyCode == UInt32(kVK_ANSI_N))
        #expect(spec?.carbonModifiers == UInt32(controlKey | optionKey))
    }

    @Test("modifier aliases: cmd/command, opt/option/alt, ctrl/control")
    func aliases() {
        let viaShort = HotKeySpec.parse("cmd+opt+k")
        let viaLong = HotKeySpec.parse("command+option+k")
        #expect(viaShort != nil)
        #expect(viaShort == viaLong)
        #expect(viaShort?.carbonModifiers == UInt32(cmdKey | optionKey))
    }

    @Test("space and digits are valid keys")
    func spaceAndDigits() {
        #expect(HotKeySpec.parse("cmd+shift+space")?.keyCode == UInt32(kVK_Space))
        #expect(HotKeySpec.parse("ctrl+alt+1")?.keyCode == UInt32(kVK_ANSI_1))
        #expect(HotKeySpec.parse("ctrl+alt+0")?.keyCode == UInt32(kVK_ANSI_0))
    }

    @Test("case and surrounding whitespace are ignored")
    func normalization() {
        #expect(HotKeySpec.parse(" CTRL + ALT + N ") == HotKeySpec.parse("ctrl+alt+n"))
    }

    @Test("a bare key with no modifier is rejected")
    func bareKeyRejected() {
        #expect(HotKeySpec.parse("n") == nil)
        #expect(HotKeySpec.parse("space") == nil)
    }

    @Test("unknown tokens are rejected")
    func unknownRejected() {
        #expect(HotKeySpec.parse("ctrl+alt+escape") == nil)
        #expect(HotKeySpec.parse("hyper+n") == nil)
        #expect(HotKeySpec.parse("") == nil)
        #expect(HotKeySpec.parse("ctrl+alt") == nil)
    }

    @Test("default spec is ctrl+alt+n")
    func defaultSpec() {
        #expect(HotKeySpec.default == HotKeySpec.parse("ctrl+alt+n"))
    }
}
