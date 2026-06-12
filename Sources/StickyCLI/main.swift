import AppKit
import Foundation
import StickyGridCore

// sticky — capture a note from the shell through stickygrid://new, or read
// the store back with list/cat. All the logic lives (tested) in
// StickyGridCore; this file is glue.

let usage = """
usage: sticky [options] [--] [words...]
       <command> | sticky [options]
       sticky list
       sticky cat [-m] <id-prefix or title words>

Creates a StickyGrid note. Words join into the note body; with no words,
the body is read from piped stdin. `list` and `cat` read your existing
notes (read-only); use `sticky -- list` to capture the word "list".

options:
  -t, --title <text>   first line of the note
  -c, --color <name>   yellow pink blue green purple orange gray white
  -m, --markdown       capture: style the body as markdown on arrival
                       cat: print the note as markdown, styles intact
      --print          print the stickygrid:// URL instead of opening it
  -h, --help           show this help

examples:
  sticky Buy milk
  git log --oneline -5 | sticky -t "Release notes" -c blue
  sticky cat -m release | pbcopy
  sticky cat -m release | sticky -m -t "Release (copy)"
"""

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let command: CaptureCommand
do {
    command = try CaptureCommand.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    let reason = switch error {
    case .unknownOption(let flag): "unknown option \(flag)"
    case .missingValue(let flag): "\(flag) needs a value"
    case .unknownColor(let name): "unknown color \"\(name)\""
    }
    fail("sticky: \(reason)\n\n" + usage, code: 64)
}

// The read-only subcommands look straight at the app's store on disk —
// they never write, so running them while StickyGrid is open is safe.
let storeDir = NoteListing.storeDirectory(
    environment: ProcessInfo.processInfo.environment,
    home: FileManager.default.homeDirectoryForCurrentUser)

func loadRecords() -> [NoteRecord] {
    guard let data = try? Data(contentsOf: storeDir.appendingPathComponent("notes.json")),
          let document = try? NotesDocument.decode(from: data)
    else { return [] }
    return document.notes
}

switch command {
case .help:
    print(usage)
    exit(0)
case .list:
    let records = loadRecords()
    if records.isEmpty { print("no notes"); exit(0) }
    NoteListing.lines(for: records).forEach { print($0) }
    exit(0)
case .cat(let query, let markdown):
    let records = loadRecords()
    switch NoteListing.match(query, in: records) {
    case .none:
        fail("sticky: no note matching \"\(query)\"", code: 1)
    case .many(let hits):
        let lines = NoteListing.lines(for: hits).joined(separator: "\n")
        fail("sticky: \"\(query)\" matches several notes:\n" + lines, code: 1)
    case .one(let record):
        let rtfURL = storeDir.appendingPathComponent("\(record.id.uuidString).rtf")
        // init?(rtf:) is not registered in headless processes — go through
        // the document-reading initializer instead.
        if let data = try? Data(contentsOf: rtfURL),
           let text = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil) {
            if markdown {
                // Same classifier as the app's export path: font traits for
                // bold/italic, Menlo prefix marks code spans.
                print(MarkdownExport.markdown(of: text) { attrs in
                    let font = attrs[.font] as? NSFont
                    let traits = font.map(NSFontManager.shared.traits(of:)) ?? []
                    let strike = attrs[.strikethroughStyle] as? Int ?? 0
                    return MarkdownExport.Style(
                        bold: traits.contains(.boldFontMask),
                        italic: traits.contains(.italicFontMask),
                        strikethrough: strike != 0,
                        code: font?.fontName.hasPrefix("Menlo") ?? false)
                })
            } else {
                print(text.string)
            }
        }
        exit(0)
    }
case .new:
    break
}

guard case .new(var body, let title, let color, let printOnly, let markdown) = command else {
    exit(0)  // unreachable — every other case exited above
}

// No words on the command line: take the body from a pipe, but never
// block waiting for a human at an interactive prompt.
if body == nil, isatty(0) == 0 {
    let piped = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
    body = piped?.trimmingCharacters(in: .whitespacesAndNewlines)
    if body?.isEmpty == true { body = nil }
}
guard body != nil || title != nil else {
    fail(usage, code: 64)
}

let url = CaptureRequest.captureURL(body: body, title: title, color: color,
                                    markdown: markdown)

if printOnly {
    print(url.absoluteString)
    exit(0)
}

// /usr/bin/open routes through LaunchServices, exactly like every other
// capture path — the GUI app must be built and registered for the scheme.
let open = Process()
open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
open.arguments = [url.absoluteString]
do {
    try open.run()
} catch {
    fail("sticky: could not run /usr/bin/open: \(error.localizedDescription)", code: 1)
}
open.waitUntilExit()
if open.terminationStatus != 0 {
    fail("sticky: open failed — is StickyGrid.app built and registered for stickygrid:// ?",
         code: open.terminationStatus)
}
