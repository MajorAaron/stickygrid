import Testing
@testable import StickyGridApp

@Suite("Note AI actions")
@MainActor
struct NoteAIActionTests {
    @Test("presets are the three fixed transforms, without ask")
    func presetsAreFixedTransforms() {
        #expect(NoteAIAction.presets == [.summarize, .checklist, .polish])
    }

    @Test("ask prompt carries the user's instruction verbatim")
    func askPromptCarriesInstruction() {
        let action = NoteAIAction.ask("Translate the note into Spanish")
        #expect(action.systemPrompt.contains("Translate the note into Spanish"))
    }

    @Test("ask prompt keeps the shared plain-text output contract")
    func askPromptKeepsOutputContract() {
        let prompt = NoteAIAction.ask("Make it rhyme").systemPrompt
        #expect(prompt.contains("Return ONLY the new note text"))
        #expect(prompt.contains("first line"))
    }

    @Test("ids are stable and unique")
    func idsAreStableAndUnique() {
        let all = NoteAIAction.presets + [.ask("anything")]
        let ids = all.map(\.id)
        #expect(ids == ["summarize", "checklist", "polish", "ask"])
        #expect(Set(ids).count == ids.count)
    }

    @Test("ask has a menu-worthy title")
    func askTitle() {
        #expect(NoteAIAction.ask("x").title == "Ask AI")
    }
}
