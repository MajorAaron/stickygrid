import AppKit

/// Programmatic main menu. The Edit menu's standard items are required —
/// without them ⌘Z/⌘X/⌘C/⌘V/⌘A never reach the text views.
enum MainMenuBuilder {
    static func build(windowManager: WindowManager) -> NSMenu {
        let main = NSMenu()

        // App
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About StickyGrid",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit StickyGrid",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        main.addItem(submenu(appMenu, title: "StickyGrid"))

        // File
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(targeted("New Note", #selector(WindowManager.newNote(_:)),
                                  "n", windowManager))
        let fromClipboard = targeted(
            "New Note from Clipboard",
            #selector(WindowManager.newNoteFromClipboard(_:)), "n", windowManager)
        fromClipboard.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(fromClipboard)
        // No key equivalent: the global ⌃⌥N hotkey already fires in-app, and
        // a menu equivalent on the same combo would double-trigger it.
        fileMenu.addItem(targeted("Quick Capture (⌃⌥N anywhere)",
                                  #selector(WindowManager.quickCapture(_:)),
                                  "", windowManager))
        fileMenu.addItem(.separator())
        let importMarkdown = targeted(
            "Import Markdown…",
            #selector(WindowManager.importMarkdownFiles(_:)), "i", windowManager)
        importMarkdown.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(importMarkdown)
        fileMenu.addItem(targeted("Share Note", #selector(WindowManager.shareFrontNote(_:)),
                                  "", windowManager))
        let copyMarkdown = targeted(
            "Copy as Markdown",
            #selector(WindowManager.copyFrontNoteAsMarkdown(_:)), "c", windowManager)
        copyMarkdown.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(copyMarkdown)
        let copyLink = targeted(
            "Copy Link to Note",
            #selector(WindowManager.copyFrontNoteLink(_:)), "c", windowManager)
        copyLink.keyEquivalentModifierMask = [.command, .option, .shift]
        fileMenu.addItem(copyLink)
        let exportMarkdown = targeted(
            "Export Note as Markdown…",
            #selector(WindowManager.exportFrontNoteAsMarkdown(_:)), "e", windowManager)
        exportMarkdown.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(exportMarkdown)
        let exportAll = targeted(
            "Export All Notes…",
            #selector(WindowManager.exportAllNotesAsMarkdown(_:)), "e", windowManager)
        exportAll.keyEquivalentModifierMask = [.command, .shift, .option]
        fileMenu.addItem(exportAll)
        fileMenu.addItem(.separator())
        fileMenu.addItem(targeted("Delete Note", #selector(WindowManager.deleteFrontNote(_:)),
                                  "w", windowManager))
        main.addItem(submenu(fileMenu, title: "File"))

        // Edit
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(targeted("Find in Notes…",
                                  #selector(WindowManager.findInNotes(_:)), "f", windowManager))
        main.addItem(submenu(editMenu, title: "Edit"))

        // Format — nil-target so actions reach the focused note's text view.
        let formatMenu = NSMenu(title: "Format")
        formatMenu.addItem(withTitle: "Bold",
                           action: #selector(StickyTextView.noteToggleBold(_:)),
                           keyEquivalent: "b")
        formatMenu.addItem(withTitle: "Italic",
                           action: #selector(StickyTextView.noteToggleItalic(_:)),
                           keyEquivalent: "i")
        formatMenu.addItem(withTitle: "Underline",
                           action: #selector(NSText.underline(_:)),
                           keyEquivalent: "u")
        let strike = NSMenuItem(title: "Strikethrough",
                                action: #selector(StickyTextView.toggleStrikethrough(_:)),
                                keyEquivalent: "x")
        strike.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(strike)
        formatMenu.addItem(.separator())
        let bullets = NSMenuItem(title: "Bullet List",
                                 action: #selector(StickyTextView.toggleBulletList(_:)),
                                 keyEquivalent: "l")
        bullets.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(bullets)
        main.addItem(submenu(formatMenu, title: "Format"))

        // AI — transforms run on the focused note.
        let aiMenu = NSMenu(title: "AI")
        aiMenu.addItem(targeted("Summarize Note",
                                #selector(WindowManager.aiSummarizeNote(_:)), "", windowManager))
        aiMenu.addItem(targeted("Turn Into Checklist",
                                #selector(WindowManager.aiChecklistNote(_:)), "", windowManager))
        aiMenu.addItem(targeted("Polish Writing",
                                #selector(WindowManager.aiPolishNote(_:)), "", windowManager))
        aiMenu.addItem(targeted("Suggest Note Color",
                                #selector(WindowManager.aiSuggestColorNote(_:)), "", windowManager))
        aiMenu.addItem(targeted("Suggest Note Title",
                                #selector(WindowManager.aiSuggestTitleNote(_:)), "", windowManager))
        aiMenu.addItem(targeted("Find Related Notes",
                                #selector(WindowManager.aiFindRelatedNotes(_:)), "", windowManager))
        let askAI = targeted("Ask AI…",
                             #selector(WindowManager.aiAskNote(_:)), "a", windowManager)
        askAI.keyEquivalentModifierMask = [.command, .option]
        aiMenu.addItem(askAI)
        let askNotes = targeted("Ask Your Notes…",
                                #selector(WindowManager.aiAskNotes(_:)), "a", windowManager)
        askNotes.keyEquivalentModifierMask = [.command, .option, .shift]
        aiMenu.addItem(askNotes)
        aiMenu.addItem(.separator())
        // Checkmark state comes from WindowManager.validateMenuItem.
        aiMenu.addItem(targeted(
            "Auto-Color Captured Notes",
            #selector(WindowManager.toggleAutoColorCapture(_:)), "", windowManager))
        aiMenu.addItem(targeted(
            "Auto-Title Captured Notes",
            #selector(WindowManager.toggleAutoTitleCapture(_:)), "", windowManager))
        aiMenu.addItem(.separator())
        aiMenu.addItem(targeted("Set Anthropic API Key…",
                                #selector(WindowManager.setAnthropicAPIKey(_:)), "", windowManager))
        main.addItem(submenu(aiMenu, title: "AI"))

        // Window
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(targeted("Arrange Notes…", #selector(WindowManager.arrangeNotes(_:)),
                                    "t", windowManager))
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")
        main.addItem(submenu(windowMenu, title: "Window"))

        // Notes — rebuilt on open by the WindowManager.
        let notesMenu = NSMenu(title: "Notes")
        notesMenu.delegate = windowManager
        main.addItem(submenu(notesMenu, title: "Notes"))

        return main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func targeted(
        _ title: String, _ action: Selector, _ key: String, _ target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
