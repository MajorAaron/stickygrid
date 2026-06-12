import Foundation
import StickyGridCore
import Testing

@testable import StickyGridApp

@Suite("Auto-color on capture")
@MainActor
struct AutoColorCaptureTests {
    @Test("colors when enabled, keyed, uncolored, and non-empty")
    func allConditionsMet() {
        let request = CaptureRequest(text: "Buy milk and eggs")
        #expect(WindowManager.shouldAutoColor(
            request: request, enabled: true, hasAPIKey: true))
    }

    @Test("the setting being off wins over everything")
    func disabled() {
        let request = CaptureRequest(text: "Buy milk and eggs")
        #expect(!WindowManager.shouldAutoColor(
            request: request, enabled: false, hasAPIKey: true))
    }

    @Test("no API key means no auto-color — capture never prompts")
    func missingKey() {
        let request = CaptureRequest(text: "Buy milk and eggs")
        #expect(!WindowManager.shouldAutoColor(
            request: request, enabled: true, hasAPIKey: false))
    }

    @Test("an explicit color in the request is respected")
    func explicitColor() {
        let request = CaptureRequest(text: "Buy milk and eggs", color: .pink)
        #expect(!WindowManager.shouldAutoColor(
            request: request, enabled: true, hasAPIKey: true))
    }

    @Test("empty or whitespace-only text has nothing to read")
    func emptyText() {
        #expect(!WindowManager.shouldAutoColor(
            request: CaptureRequest(text: ""), enabled: true, hasAPIKey: true))
        #expect(!WindowManager.shouldAutoColor(
            request: CaptureRequest(text: " \n\t"), enabled: true, hasAPIKey: true))
    }

    @Test("the setting round-trips through UserDefaults and defaults to off")
    func settingRoundTrip() {
        let key = "AIAutoColorCapture"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(!WindowManager.autoColorCaptureEnabled)

        WindowManager.autoColorCaptureEnabled = true
        #expect(WindowManager.autoColorCaptureEnabled)
        #expect(UserDefaults.standard.bool(forKey: key))

        WindowManager.autoColorCaptureEnabled = false
        #expect(!WindowManager.autoColorCaptureEnabled)
    }
}
