import Foundation

/// One parsed invocation of the `sticky` command-line tool, which captures
/// notes from the shell through the `stickygrid://new` URL scheme.
///
/// `sticky [--title v] [--color v] [--print] [--] [words...]`
/// Positional words join into the body; no positionals leaves the body nil
/// so the executable can fill it from stdin.
///
/// A first argument of exactly `list` or `cat` dispatches the read-only
/// subcommands instead (`sticky -- list` escapes back to capture).
public enum CaptureCommand: Equatable, Sendable {
    case help
    case new(body: String?, title: String?, color: NoteColor?, printOnly: Bool)
    case list
    case cat(query: String, markdown: Bool)

    public enum ParseError: Error, Equatable {
        case unknownOption(String)
        case missingValue(String)
        case unknownColor(String)
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
        default:
            break
        }

        var words: [String] = []
        var title: String?
        var color: NoteColor?
        var printOnly = false
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
            case _ where arg.hasPrefix("-") && arg.count > 1:
                throw .unknownOption(arg)
            default:
                words.append(arg)
            }
            index = args.index(after: index)
        }

        return .new(body: words.isEmpty ? nil : words.joined(separator: " "),
                    title: title, color: color, printOnly: printOnly)
    }
}
