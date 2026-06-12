# Auto-Title on Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Captured notes quietly give themselves an AI title when a new AI-menu checkbox is on, mirroring Auto-Color on Capture.

**Architecture:** A pure decision rule `WindowManager.shouldAutoTitle` gates a quiet variant of the existing Suggest Title flow. `CaptureRequest` learns whether its title was explicitly chosen by the caller. Both quiet AI actions refactor into awaitable cores so capture can chain them (title first, then color) without tripping the `aiBusy` guard.

**Tech Stack:** Swift 6 / SwiftPM, swift-testing (`@Test`/`#expect`), AppKit. The StickyGridApp module uses main-actor default isolation — app test suites need `@MainActor`.

Spec: `docs/superpowers/specs/2026-06-12-auto-title-capture-design.md`

---

### Task 1: Core — `CaptureRequest.hasExplicitTitle`

**Files:**
- Modify: `Sources/StickyGridCore/NoteCapture.swift`
- Test: `Tests/StickyGridCoreTests/CaptureRequestTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `CaptureRequestTests` (inside the `// MARK: stickygrid:// URLs` section, after `bodyAlias`):

```swift
@Test("an explicit title= param is remembered")
func explicitTitleRemembered() throws {
    let url = try #require(URL(string: "stickygrid://new?title=Groceries&text=milk"))
    #expect(CaptureRequest.from(url: url)?.hasExplicitTitle == true)
}

@Test("text-only URLs, bare new, and empty title are not explicit titles")
func noExplicitTitle() throws {
    let textOnly = try #require(URL(string: "stickygrid://new?text=milk"))
    #expect(CaptureRequest.from(url: textOnly)?.hasExplicitTitle == false)
    let bare = try #require(URL(string: "stickygrid://new"))
    #expect(CaptureRequest.from(url: bare)?.hasExplicitTitle == false)
    let emptyTitle = try #require(URL(string: "stickygrid://new?title=&text=milk"))
    #expect(CaptureRequest.from(url: emptyTitle)?.hasExplicitTitle == false)
}

@Test("plain text capture never has an explicit title")
func plainTextNoExplicitTitle() {
    #expect(CaptureRequest.from(plainText: "hello")?.hasExplicitTitle == false)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CaptureRequestTests`
Expected: COMPILE ERROR — `value of type 'CaptureRequest' has no member 'hasExplicitTitle'`

- [ ] **Step 3: Implement**

In `Sources/StickyGridCore/NoteCapture.swift`, add the stored property and extend the init (default keeps existing call sites compiling):

```swift
public var text: String
public var color: NoteColor?
/// True when the capture's first line was explicitly chosen by the
/// caller (the URL scheme's `title=` param) rather than derived from
/// the body — auto-title must not stack a second title on it.
public var hasExplicitTitle: Bool

public init(text: String, color: NoteColor? = nil, hasExplicitTitle: Bool = false) {
    self.text = text
    self.color = color
    self.hasExplicitTitle = hasExplicitTitle
}
```

In `from(url:)`, change the return:

```swift
let text = [title, body].compactMap(\.self).joined(separator: "\n")
return CaptureRequest(text: text, color: color,
                      hasExplicitTitle: !(title ?? "").isEmpty)
```

(`from(plainText:)` is untouched — the default `false` is correct.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CaptureRequestTests`
Expected: PASS (all, including the 3 new tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyGridCore/NoteCapture.swift Tests/StickyGridCoreTests/CaptureRequestTests.swift
git commit -m "Auto-title capture: CaptureRequest remembers an explicit title="
```

### Task 2: Decision rule and `AIAutoTitleCapture` setting

**Files:**
- Modify: `Sources/StickyGridApp/WindowManager.swift` (the `// MARK: Auto-color on capture` section, ~line 386)
- Create: `Tests/StickyGridAppTests/AutoTitleCaptureTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/StickyGridAppTests/AutoTitleCaptureTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AutoTitleCaptureTests`
Expected: COMPILE ERROR — `type 'WindowManager' has no member 'shouldAutoTitle'`

- [ ] **Step 3: Implement**

In `Sources/StickyGridApp/WindowManager.swift`, rename the section mark to `// MARK: Auto-color / auto-title on capture` and add below the auto-color members:

```swift
private nonisolated static let autoTitleCaptureKey = "AIAutoTitleCapture"

/// Off by default: auto-title spends API tokens on every capture.
nonisolated static var autoTitleCaptureEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: autoTitleCaptureKey) }
    set { UserDefaults.standard.set(newValue, forKey: autoTitleCaptureKey) }
}

/// Whether a captured note should quietly title itself. Capture must
/// never prompt, so a missing key disables it; an explicit title in
/// the request means the caller already chose.
nonisolated static func shouldAutoTitle(
    request: CaptureRequest, enabled: Bool, hasAPIKey: Bool
) -> Bool {
    enabled && hasAPIKey && !request.hasExplicitTitle
        && !request.text
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

@objc func toggleAutoTitleCapture(_ sender: Any?) {
    Self.autoTitleCaptureEnabled.toggle()
}
```

Extend `validateMenuItem` (same function, new branch):

```swift
func validateMenuItem(_ item: NSMenuItem) -> Bool {
    if item.action == #selector(toggleAutoColorCapture(_:)) {
        item.state = Self.autoColorCaptureEnabled ? .on : .off
    }
    if item.action == #selector(toggleAutoTitleCapture(_:)) {
        item.state = Self.autoTitleCaptureEnabled ? .on : .off
    }
    return true
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AutoTitleCaptureTests`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyGridApp/WindowManager.swift Tests/StickyGridAppTests/AutoTitleCaptureTests.swift
git commit -m "Auto-title capture: decision rule and AIAutoTitleCapture setting"
```

### Task 3: Quiet title path, sequential capture chain, menu item

Glue task — no new unit tests (the rule, the sanitizer, and the insert
path are covered by AutoTitleCaptureTests, NoteAITitleTests, and
TitleInsertTests); the full suite guards against regressions.

**Files:**
- Modify: `Sources/StickyGridApp/WindowManager.swift` (`createNote` ~line 48, `suggestTitle` ~line 364, `suggestColor` ~line 422)
- Modify: `Sources/StickyGridApp/MainMenuBuilder.swift` (~line 117)

- [ ] **Step 1: Refactor both suggest functions into awaitable cores**

Replace `suggestTitle(on:)` in `WindowManager.swift`:

```swift
/// Like suggestColor, but the result is inserted as a new first line —
/// the old text shifts down intact, and one undo reverts it.
private func suggestTitle(on id: UUID, quietly: Bool = false) {
    Task { @MainActor [weak self] in
        await self?.performSuggestTitle(on: id, quietly: quietly)
    }
}

/// The quiet path (auto-title on capture) never beeps, prompts, or
/// alerts — its preconditions were checked by `shouldAutoTitle`, and a
/// failed capture titling just leaves the note as it is.
private func performSuggestTitle(on id: UUID, quietly: Bool) async {
    guard let viewModel = viewModels[id], !viewModel.aiBusy else { return }
    let text = viewModel.textController.plainText()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
        if !quietly { NSSound.beep() }
        return
    }
    guard NoteAI.apiKey() != nil else {
        if !quietly { promptForAPIKey() }
        return
    }

    viewModel.aiBusy = true
    defer { viewModel.aiBusy = false }
    do {
        let title = try await NoteAI.suggestTitle(for: text)
        viewModel.textController.insertTitleLine(title)
    } catch {
        if !quietly { presentAIError(error, on: id) }
    }
}
```

Replace `suggestColor(on:quietly:)` the same way (behavior unchanged, just split so capture can await it):

```swift
/// Like runAI, but the result is a palette color instead of new text.
private func suggestColor(on id: UUID, quietly: Bool = false) {
    Task { @MainActor [weak self] in
        await self?.performSuggestColor(on: id, quietly: quietly)
    }
}

/// The quiet path (auto-color on capture) never beeps, prompts, or
/// alerts — its preconditions were checked by `shouldAutoColor`, and a
/// failed capture coloring just leaves the note as it is.
private func performSuggestColor(on id: UUID, quietly: Bool) async {
    guard let viewModel = viewModels[id], !viewModel.aiBusy else { return }
    let text = viewModel.textController.plainText()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
        if !quietly { NSSound.beep() }
        return
    }
    guard NoteAI.apiKey() != nil else {
        if !quietly { promptForAPIKey() }
        return
    }

    viewModel.aiBusy = true
    defer { viewModel.aiBusy = false }
    do {
        viewModel.colorID = try await NoteAI.suggestColor(for: text)
        appearanceChanged(id)
    } catch {
        if !quietly { presentAIError(error, on: id) }
    }
}
```

- [ ] **Step 2: Chain title then color in `createNote`**

In `createNote(from:activate:)`, replace the trailing `shouldAutoColor` block:

```swift
// Title first so the color model reads the final text; sequential
// because both actions guard on aiBusy — concurrent, the second
// would silently bail.
let autoTitle = Self.shouldAutoTitle(request: request,
                                     enabled: Self.autoTitleCaptureEnabled,
                                     hasAPIKey: NoteAI.apiKey() != nil)
let autoColor = Self.shouldAutoColor(request: request,
                                     enabled: Self.autoColorCaptureEnabled,
                                     hasAPIKey: NoteAI.apiKey() != nil)
if autoTitle || autoColor {
    let id = record.id
    Task { @MainActor [weak self] in
        if autoTitle { await self?.performSuggestTitle(on: id, quietly: true) }
        if autoColor { await self?.performSuggestColor(on: id, quietly: true) }
    }
}
```

- [ ] **Step 3: Add the AI-menu checkbox**

In `Sources/StickyGridApp/MainMenuBuilder.swift`, after the
"Auto-Color Captured Notes" item:

```swift
aiMenu.addItem(targeted(
    "Auto-Title Captured Notes",
    #selector(WindowManager.toggleAutoTitleCapture(_:)), "", windowManager))
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: BUILD PASS, all tests PASS (no regressions — `suggestTitle`/`suggestColor` call sites are unchanged thanks to the default `quietly: false`)

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyGridApp/WindowManager.swift Sources/StickyGridApp/MainMenuBuilder.swift
git commit -m "Auto-title capture: quiet title path, title-then-color chain, AI-menu toggle"
```

### Task 4: Merge

- [ ] **Step 1: Merge the feature branch**

```bash
git checkout main
git merge --no-ff auto-title-capture -m "Merge auto-title-capture: captured notes title themselves via AI"
git push origin main
```

Manual GUI verification (checkbox state, a real capture titling itself)
is deferred to the user, as with auto-color.
