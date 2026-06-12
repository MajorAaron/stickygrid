import Foundation
import Testing
@testable import StickyGridCore

@Suite("sticky CLI argument parsing")
struct CaptureCommandTests {

    @Test("positional words join into the body")
    func positionalsJoin() throws {
        let command = try CaptureCommand.parse(["Buy", "milk"])
        #expect(command == .new(body: "Buy milk", title: nil, color: nil, printOnly: false, markdown: false))
    }

    @Test("no arguments means body nil — main fills it from stdin")
    func noArgsMeansStdin() throws {
        let command = try CaptureCommand.parse([])
        #expect(command == .new(body: nil, title: nil, color: nil, printOnly: false, markdown: false))
    }

    @Test("--title and --color flags, long form")
    func longFlags() throws {
        let command = try CaptureCommand.parse(["--title", "Groceries", "--color", "pink", "milk"])
        #expect(command == .new(body: "milk", title: "Groceries", color: .pink, printOnly: false, markdown: false))
    }

    @Test("-t and -c short forms")
    func shortFlags() throws {
        let command = try CaptureCommand.parse(["-t", "Groceries", "-c", "blue"])
        #expect(command == .new(body: nil, title: "Groceries", color: .blue, printOnly: false, markdown: false))
    }

    @Test("color is case-insensitive and grey is an alias for gray")
    func colorAliases() throws {
        #expect(try CaptureCommand.parse(["-c", "Pink"])
                == .new(body: nil, title: nil, color: .pink, printOnly: false, markdown: false))
        #expect(try CaptureCommand.parse(["-c", "grey"])
                == .new(body: nil, title: nil, color: .gray, printOnly: false, markdown: false))
    }

    @Test("--print is parsed")
    func printFlag() throws {
        let command = try CaptureCommand.parse(["--print", "hi"])
        #expect(command == .new(body: "hi", title: nil, color: nil, printOnly: true, markdown: false))
    }

    @Test("-m / --markdown mark the captured body as markdown")
    func markdownFlag() throws {
        #expect(try CaptureCommand.parse(["-m", "get", "**milk**"])
                == .new(body: "get **milk**", title: nil, color: nil,
                        printOnly: false, markdown: true))
        #expect(try CaptureCommand.parse(["--markdown"])
                == .new(body: nil, title: nil, color: nil,
                        printOnly: false, markdown: true))
    }

    @Test("after -- a -m is a body word, not the markdown flag")
    func markdownFlagEscaped() throws {
        #expect(try CaptureCommand.parse(["--", "-m", "todo"])
                == .new(body: "-m todo", title: nil, color: nil,
                        printOnly: false, markdown: false))
    }

    @Test("--help wins from anywhere, even after other args")
    func helpWins() throws {
        #expect(try CaptureCommand.parse(["--help"]) == .help)
        #expect(try CaptureCommand.parse(["-t", "x", "body", "-h"]) == .help)
    }

    @Test("-- ends option parsing so a body can start with a dash")
    func doubleDash() throws {
        let command = try CaptureCommand.parse(["--", "--not-a-flag", "todo"])
        #expect(command == .new(body: "--not-a-flag todo", title: nil, color: nil, printOnly: false, markdown: false))
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

    @Test("first argument list dispatches the list subcommand")
    func listSubcommand() throws {
        #expect(try CaptureCommand.parse(["list"]) == .list)
    }

    @Test("first argument cat joins the rest into one query")
    func catSubcommand() throws {
        #expect(try CaptureCommand.parse(["cat", "groceries"])
                == .cat(query: "groceries", markdown: false))
        #expect(try CaptureCommand.parse(["cat", "release", "notes"])
                == .cat(query: "release notes", markdown: false))
    }

    @Test("cat -m / --markdown sets the markdown flag, anywhere in the args")
    func catMarkdownFlag() throws {
        #expect(try CaptureCommand.parse(["cat", "-m", "groceries"])
                == .cat(query: "groceries", markdown: true))
        #expect(try CaptureCommand.parse(["cat", "release", "--markdown"])
                == .cat(query: "release", markdown: true))
    }

    @Test("cat -- stops flag scanning so -m can be a query")
    func catDoubleDash() throws {
        #expect(try CaptureCommand.parse(["cat", "--", "-m"])
                == .cat(query: "-m", markdown: false))
    }

    @Test("other dashed words stay query text, as before")
    func catDashedQuery() throws {
        #expect(try CaptureCommand.parse(["cat", "to-do"])
                == .cat(query: "to-do", markdown: false))
    }

    @Test("cat -m with no query is still a usage error")
    func catMarkdownNeedsQuery() {
        #expect(throws: CaptureCommand.ParseError.missingValue("cat")) {
            try CaptureCommand.parse(["cat", "--markdown"])
        }
    }

    @Test("cat with no query is a usage error")
    func catNeedsQuery() {
        #expect(throws: CaptureCommand.ParseError.missingValue("cat")) {
            try CaptureCommand.parse(["cat"])
        }
    }

    @Test("first argument export takes a single directory")
    func exportSubcommand() throws {
        #expect(try CaptureCommand.parse(["export", "/tmp/notes"])
                == .export(directory: "/tmp/notes"))
    }

    @Test("export -- lets a directory start with a dash")
    func exportDoubleDash() throws {
        #expect(try CaptureCommand.parse(["export", "--", "-odd-dir"])
                == .export(directory: "-odd-dir"))
    }

    @Test("export with no directory is a usage error")
    func exportNeedsDirectory() {
        #expect(throws: CaptureCommand.ParseError.missingValue("export")) {
            try CaptureCommand.parse(["export"])
        }
    }

    @Test("export with a second positional is a usage error, not a join")
    func exportRejectsExtraArguments() {
        #expect(throws: CaptureCommand.ParseError.extraArgument("b")) {
            try CaptureCommand.parse(["export", "a", "b"])
        }
    }

    @Test("first argument open joins the rest into one query")
    func openSubcommand() throws {
        #expect(try CaptureCommand.parse(["open", "groceries"])
                == .open(query: "groceries", printOnly: false))
        #expect(try CaptureCommand.parse(["open", "release", "notes"])
                == .open(query: "release notes", printOnly: false))
    }

    @Test("open --print prints the link instead, anywhere in the args")
    func openPrintFlag() throws {
        #expect(try CaptureCommand.parse(["open", "--print", "groceries"])
                == .open(query: "groceries", printOnly: true))
        #expect(try CaptureCommand.parse(["open", "release", "--print"])
                == .open(query: "release", printOnly: true))
    }

    @Test("open -- stops flag scanning so --print can be a query")
    func openDoubleDash() throws {
        #expect(try CaptureCommand.parse(["open", "--", "--print"])
                == .open(query: "--print", printOnly: false))
    }

    @Test("open keeps other dashed words as query text")
    func openDashedQuery() throws {
        #expect(try CaptureCommand.parse(["open", "to-do"])
                == .open(query: "to-do", printOnly: false))
    }

    @Test("open with no query is a usage error")
    func openNeedsQuery() {
        #expect(throws: CaptureCommand.ParseError.missingValue("open")) {
            try CaptureCommand.parse(["open"])
        }
        #expect(throws: CaptureCommand.ParseError.missingValue("open")) {
            try CaptureCommand.parse(["open", "--print"])
        }
    }

    @Test("-- open is still a captured note body, not a subcommand")
    func dashDashEscapesOpen() throws {
        #expect(try CaptureCommand.parse(["--", "open"])
                == .new(body: "open", title: nil, color: nil, printOnly: false, markdown: false))
    }

    @Test("-- export is still a captured note body, not a subcommand")
    func dashDashEscapesExport() throws {
        #expect(try CaptureCommand.parse(["--", "export"])
                == .new(body: "export", title: nil, color: nil, printOnly: false, markdown: false))
    }

    @Test("-- list is still a captured note body, not a subcommand")
    func dashDashEscapesSubcommand() throws {
        #expect(try CaptureCommand.parse(["--", "list"])
                == .new(body: "list", title: nil, color: nil, printOnly: false, markdown: false))
    }

    @Test("subcommands only dispatch from the first argument")
    func subcommandMustBeFirst() throws {
        #expect(try CaptureCommand.parse(["-t", "x", "list"])
                == .new(body: "list", title: "x", color: nil, printOnly: false, markdown: false))
    }
}
