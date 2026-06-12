import Foundation
import Testing
@testable import StickyGridCore

@Suite("sticky CLI argument parsing")
struct CaptureCommandTests {

    @Test("positional words join into the body")
    func positionalsJoin() throws {
        let command = try CaptureCommand.parse(["Buy", "milk"])
        #expect(command == .new(body: "Buy milk", title: nil, color: nil, printOnly: false))
    }

    @Test("no arguments means body nil — main fills it from stdin")
    func noArgsMeansStdin() throws {
        let command = try CaptureCommand.parse([])
        #expect(command == .new(body: nil, title: nil, color: nil, printOnly: false))
    }

    @Test("--title and --color flags, long form")
    func longFlags() throws {
        let command = try CaptureCommand.parse(["--title", "Groceries", "--color", "pink", "milk"])
        #expect(command == .new(body: "milk", title: "Groceries", color: .pink, printOnly: false))
    }

    @Test("-t and -c short forms")
    func shortFlags() throws {
        let command = try CaptureCommand.parse(["-t", "Groceries", "-c", "blue"])
        #expect(command == .new(body: nil, title: "Groceries", color: .blue, printOnly: false))
    }

    @Test("color is case-insensitive and grey is an alias for gray")
    func colorAliases() throws {
        #expect(try CaptureCommand.parse(["-c", "Pink"])
                == .new(body: nil, title: nil, color: .pink, printOnly: false))
        #expect(try CaptureCommand.parse(["-c", "grey"])
                == .new(body: nil, title: nil, color: .gray, printOnly: false))
    }

    @Test("--print is parsed")
    func printFlag() throws {
        let command = try CaptureCommand.parse(["--print", "hi"])
        #expect(command == .new(body: "hi", title: nil, color: nil, printOnly: true))
    }

    @Test("--help wins from anywhere, even after other args")
    func helpWins() throws {
        #expect(try CaptureCommand.parse(["--help"]) == .help)
        #expect(try CaptureCommand.parse(["-t", "x", "body", "-h"]) == .help)
    }

    @Test("-- ends option parsing so a body can start with a dash")
    func doubleDash() throws {
        let command = try CaptureCommand.parse(["--", "--not-a-flag", "todo"])
        #expect(command == .new(body: "--not-a-flag todo", title: nil, color: nil, printOnly: false))
    }

    @Test("unknown option is an error")
    func unknownOption() {
        #expect(throws: CaptureCommand.ParseError.unknownOption("--frobnicate")) {
            try CaptureCommand.parse(["--frobnicate"])
        }
    }

    @Test("flag at the end with no value is an error")
    func missingValue() {
        #expect(throws: CaptureCommand.ParseError.missingValue("--title")) {
            try CaptureCommand.parse(["--title"])
        }
    }

    @Test("unknown color is an error, not silently ignored")
    func unknownColor() {
        #expect(throws: CaptureCommand.ParseError.unknownColor("chartreuse")) {
            try CaptureCommand.parse(["-c", "chartreuse"])
        }
    }
}
