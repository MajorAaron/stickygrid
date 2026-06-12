import Foundation
import StickyGridCore

// sticky — capture a note from the shell through stickygrid://new.
// All the logic lives (tested) in StickyGridCore; this file is glue.

let usage = """
usage: sticky [options] [--] [words...]
       <command> | sticky [options]

Creates a StickyGrid note. Words join into the note body; with no words,
the body is read from piped stdin.

options:
  -t, --title <text>   first line of the note
  -c, --color <name>   yellow pink blue green purple orange gray white
      --print          print the stickygrid:// URL instead of opening it
  -h, --help           show this help

examples:
  sticky Buy milk
  git log --oneline -5 | sticky -t "Release notes" -c blue
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

guard case .new(var body, let title, let color, let printOnly) = command else {
    print(usage)
    exit(0)
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

let url = CaptureRequest.captureURL(body: body, title: title, color: color)

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
