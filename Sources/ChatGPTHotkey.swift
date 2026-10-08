import CoreGraphics
import Foundation

/// ChatGPT's "Voice Chat hotkey" (Settings → Keyboard shortcuts): a system-wide shortcut that
/// starts a voice chat, or stops or cancels the one that's running or still starting, without
/// bringing ChatGPT to the front. It has no default, so Hey AI adds one to ChatGPT's
/// keybindings file. ChatGPT reads that file when it starts; a shortcut changed in ChatGPT's
/// own settings works right away.
enum ChatGPTHotkey {
    static let command = "realtimeVoice"
    static let defaultKey = "Control+Alt+Command+V"
    static let defaultKeySymbols = "⌃⌥⌘V"

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/keybindings.json")
    }

    enum Binding: Equatable {
        /// ChatGPT has no voice hotkey (it ships without one).
        case none
        /// Someone removed it in ChatGPT's settings, which ChatGPT records as a null key.
        case cleared
        case set(String)
        /// The file isn't the list of bindings ChatGPT writes.
        case unreadable
    }

    static func binding(in data: Data?) -> Binding {
        guard let entries = bindings(in: data) else { return .unreadable }
        guard let entry = entries.last(where: { $0["command"] as? String == command }) else { return .none }
        return (entry["key"] as? String).map(Binding.set) ?? .cleared
    }

    /// The shortcut ChatGPT has for voice chat, or nil if there's none.
    static func key(in data: Data?) -> String? {
        if case .set(let key) = binding(in: data) { return key }
        return nil
    }

    /// The file with the voice hotkey added, or nil unless ChatGPT has none: a hotkey you set
    /// or cleared is left as it is, and so is a file Hey AI can't read.
    static func adding(_ key: String = defaultKey, to data: Data?) -> Data? {
        guard binding(in: data) == .none, var entries = bindings(in: data) else { return nil }
        entries.append(["command": command, "key": key])
        return try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
    }

    /// No file (or an empty one) is an empty list, like ChatGPT treats it.
    private static func bindings(in data: Data?) -> [[String: Any]]? {
        guard let data, !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              list.allSatisfy({ $0["command"] is String }) else { return nil }
        return list
    }

    /// An Electron accelerator such as "Control+Alt+Command+V" as a key and modifiers. Only
    /// letters, digits and space (a posted F19 shortcut didn't fire in testing).
    static func parse(_ accelerator: String) -> (key: CGKeyCode, flags: CGEventFlags)? {
        var flags: CGEventFlags = []
        var key: CGKeyCode?
        for part in accelerator.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            switch part {
            case "control", "ctrl": flags.insert(.maskControl)
            case "alt", "option": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            case "command", "cmd", "cmdorctrl", "commandorcontrol", "super": flags.insert(.maskCommand)
            default:
                guard key == nil, let code = keyCodes[part] else { return nil }
                key = code
            }
        }
        guard let key, !flags.isEmpty else { return nil }
        return (key, flags)
    }

    /// US-layout key codes (kVK_ANSI_*).
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46, "space": 49,
    ]
}
