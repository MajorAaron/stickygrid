import Foundation
import StickyGridCore
import Testing

@testable import StickyGridApp

@Suite("Auto-title on capture")
@MainActor
struct AutoTitleCaptureTests {
    @Test("titles when enabled, keyed, untitled, and non-empty")
    func allConditionsMet() {
        let request = CaptureRequest(text: "Buy milk and eggs")
        #expect(WindowManager.shouldAutoTitle(
            request: request, enabled: true, hasAPIKey: true))
    }

    @Test("the setting being off wins over everything")
    func disabled() {
        let request = CaptureRequest(text: "Buy milk and eggs")
        #expect(!WindowManager.shouldAutoTitle(
            request: request, enabled: false, hasAPIKey: true))
    }

    @Test("no API key means no auto-title — capture never prompts")
    func missingKey() {
        let request = CaptureRequest(text: "Buy milk and eggs")
        #expect(!WindowManager.shouldAutoTitle(
            request: request, enabled: true, hasAPIKey: false))
    }

    @Test("an explicit title in the request is respected")
    func explicitTitle() {
        let request = CaptureRequest(text: "Groceries\nmilk",
                                     hasExplicitTitle: true)
        #expect(!WindowManager.shouldAutoTitle(
            request: request, enabled: true, hasAPIKey: true))
    }

    @Test("empty or whitespace-only text has nothing to title")
    func emptyText() {
        #expect(!WindowManager.shouldAutoTitle(
            request: CaptureRequest(text: ""), enabled: true, hasAPIKey: true))
        #expect(!WindowManager.shouldAutoTitle(
            request: CaptureRequest(text: " \n\t"), enabled: true, hasAPIKey: true))
    }

    @Test("the setting round-trips through UserDefaults and defaults to off")
    func settingRoundTrip() {
        let key = "AIAutoTitleCapture"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(!WindowManager.autoTitleCaptureEnabled)

        WindowManager.autoTitleCaptureEnabled = true
        #expect(WindowManager.autoTitleCaptureEnabled)
        #expect(UserDefaults.standard.bool(forKey: key))

        WindowManager.autoTitleCaptureEnabled = false
        #expect(!WindowManager.autoTitleCaptureEnabled)
    }
}
