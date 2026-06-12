import Foundation

/// One parsed invocation of the `sticky` command-line tool, which captures
/// notes from the shell through the `stickygrid://new` URL scheme.
///
/// `sticky [--title v] [--color v] [--markdown] [--print] [--] [words...]`
/// Positional words join into the body; no positionals leaves the body nil
/// so the executable can fill it from stdin.
///
/// A first argument of exactly `list`, `cat`, `open`, or `export` dispatches
/// the subcommands instead (`sticky -- list` escapes back to capture).
public enum CaptureCommand: Equatable, Sendable {
    case help
    case new(body: String?, title: String?, color: NoteColor?, printOnly: Bool,
             markdown: Bool)
    case list
    case cat(query: String, markdown: Bool)
    case open(query: String, printOnly: Bool)
    case export(directory: String)

    public enum ParseError: Error, Equatable {
        case unknownOption(String)
        case missingValue(String)
        case unknownColor(String)
        case extraArgument(String)
    }

    public static func parse(_ args: [String]) throws(ParseError) -> CaptureCommand {
        switch args.first {
        case "list":
            return .list
        case "cat":
            // Only -m/--markdown is an option here; other dashed words stay
            // query text since titles may contain dashes. `--` escapes -m.
            var markdown = false
            var scanningFlags = true
            var queryWords: [String] = []
            for arg in args.dropFirst() {
                if scanningFlags, arg == "--" {
                    scanningFlags = false
                } else if scanningFlags, arg == "-m" || arg == "--markdown" {
                    markdown = true
                } else {
                    queryWords.append(arg)
                }
            }
            guard !queryWords.isEmpty else { throw .missingValue("cat") }
            return .cat(query: queryWords.joined(separator: " "), markdown: markdown)
        case "open":
            // Same scanning rule as cat: only --print is an option, `--`
            // escapes it, other dashed words stay query text.
            var printOnly = false
            var scanningFlags = true
            var queryWords: [String] = []
            for arg in args.dropFirst() {
                if scanningFlags, arg == "--" {
                    scanningFlags = false
                } else if scanningFlags, arg == "--print" {
                    printOnly = true
                } else {
                    queryWords.append(arg)
                }
            }
            guard !queryWords.isEmpty else { throw .missingValue("open") }
            return .open(query: queryWords.joined(separator: " "), printOnly: printOnly)
        case "export":
            // Exactly one directory; a path with spaces is one shell-quoted
            // argument, so a second positional is always a mistake. A
            // leading `--` lets the directory itself start with a dash.
            var positionals = Array(args.dropFirst())
            if positionals.first == "--" { positionals.removeFirst() }
            guard let directory = positionals.first else {
                throw .missingValue("export")
            }
            guard positionals.count == 1 else {
                throw .extraArgument(positionals[1])
            }
            return .export(directory: directory)
        default:
            break
        }

        var words: [String] = []
        var title: String?
        var color: NoteColor?
        var printOnly = false
        var markdown = false
        var optionsEnded = false
        var index = args.startIndex

        func value(for flag: String) throws(ParseError) -> String {
            index = args.index(after: index)
            guard index < args.endIndex else { throw .missingValue(flag) }
            return args[index]
        }

        while index < args.endIndex {
            let arg = args[index]
            switch arg {
            case _ where optionsEnded:
                words.append(arg)
            case "--":
                optionsEnded = true
            case "-h", "--help":
                return .help
            case "-t", "--title":
                title = try value(for: arg)
            case "-c", "--color":
                let raw = try value(for: arg)
                let name = raw.lowercased()
                guard let parsed = NoteColor(rawValue: name == "grey" ? "gray" : name) else {
                    throw .unknownColor(raw)
                }
                color = parsed
            case "--print":
                printOnly = true
            case "-m", "--markdown":
                markdown = true
            case _ where arg.hasPrefix("-") && arg.count > 1:
                throw .unknownOption(arg)
            default:
                words.append(arg)
            }
            index = args.index(after: index)
        }

        return .new(body: words.isEmpty ? nil : words.joined(separator: " "),
                    title: title, color: color, printOnly: printOnly,
                    markdown: markdown)
    }
}
