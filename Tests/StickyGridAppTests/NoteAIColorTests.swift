import StickyGridCore
import Testing

@testable import StickyGridApp

@Suite("AI color suggestion")
@MainActor
struct NoteAIColorTests {
    @Test("bare color name parses")
    func bareName() {
        #expect(NoteColor(aiReply: "green") == .green)
    }

    @Test("casing, whitespace, and punctuation are tolerated")
    func punctuationAndCasing() {
        #expect(NoteColor(aiReply: "  Purple.\n") == .purple)
        #expect(NoteColor(aiReply: "ORANGE!") == .orange)
    }

    @Test("a verbose reply still yields the named color")
    func verboseReply() {
        #expect(NoteColor(aiReply: "I'd pick blue because it reads calm.") == .blue)
    }

    @Test("the earliest-mentioned color wins")
    func earliestMentionWins() {
        #expect(NoteColor(aiReply: "orange, not yellow") == .orange)
        #expect(NoteColor(aiReply: "yellow beats orange here") == .yellow)
    }

    @Test("the grey spelling maps to gray")
    func greySpelling() {
        #expect(NoteColor(aiReply: "grey") == .gray)
    }

    @Test("replies naming no known color return nil")
    func unknownColor() {
        #expect(NoteColor(aiReply: "teal") == nil)
        #expect(NoteColor(aiReply: "") == nil)
        #expect(NoteColor(aiReply: "no color fits") == nil)
    }

    @Test("the system prompt offers every NoteColor and demands one word")
    func systemPromptCoversPalette() {
        let prompt = NoteAI.colorSystemPrompt
        for color in NoteColor.allCases {
            #expect(prompt.contains(color.rawValue))
        }
        #expect(prompt.lowercased().contains("one word"))
    }
}
