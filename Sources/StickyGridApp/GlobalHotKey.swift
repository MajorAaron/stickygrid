import Carbon.HIToolbox
import Foundation

/// A parsed global-shortcut description like "ctrl+alt+n".
///
/// The Quick Capture shortcut is remappable without UI:
/// `defaults write com.stickygrid.app QuickCaptureHotKey "cmd+shift+space"`.
/// Keys are letters, digits, or `space`; at least one modifier is required
/// (a bare key would swallow normal typing system-wide).
nonisolated struct HotKeySpec: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let `default` = HotKeySpec(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(controlKey | optionKey))

    static func parse(_ raw: String) -> HotKeySpec? {
        let tokens = raw.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard tokens.count >= 2, let key = tokens.last else { return nil }

        var modifiers: UInt32 = 0
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "alt", "opt", "option": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        guard modifiers != 0, let keyCode = Self.keyCodes[key] else { return nil }
        return HotKeySpec(keyCode: keyCode, carbonModifiers: modifiers)
    }

    private static let keyCodes: [String: UInt32] = {
        let ansi: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C),
            ("d", kVK_ANSI_D), ("e", kVK_ANSI_E), ("f", kVK_ANSI_F),
            ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I),
            ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R),
            ("s", kVK_ANSI_S), ("t", kVK_ANSI_T), ("u", kVK_ANSI_U),
            ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2),
            ("3", kVK_ANSI_3), ("4", kVK_ANSI_4), ("5", kVK_ANSI_5),
            ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9), ("space", kVK_Space),
        ]
        return Dictionary(uniqueKeysWithValues: ansi.map { ($0, UInt32($1)) })
    }()
}

/// Registers a system-wide hotkey via Carbon's RegisterEventHotKey — the one
/// global-shortcut API that needs no Accessibility or Input Monitoring
/// permission. Fires even when StickyGrid is not the active app.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void

    init?(spec: HotKeySpec, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData)
                .takeUnretainedValue()
            // Carbon delivers application-target events on the main thread.
            MainActor.assumeIsolated { hotKey.handler() }
            return noErr
        }
        guard InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef) == noErr
        else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5347_4844),  // 'SGHD'
                                     id: 1)
        guard RegisterEventHotKey(
            spec.keyCode, spec.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
        else {
            RemoveEventHandler(handlerRef)
            handlerRef = nil
            return nil
        }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
