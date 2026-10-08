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

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/keybindings.json")
    }

    /// The shortcut ChatGPT has for voice chat, or nil if there's none (or it was cleared).
    static func key(in data: Data?) -> String? {
        guard let entries = bindings(in: data) else { return nil }
        return entries.last { $0["command"] as? String == command }?["key"] as? String
    }

    /// The file with the voice hotkey added, or nil when it should be left alone: the user
    /// already set or cleared one, or the file isn't the list of bindings ChatGPT writes.
    static func adding(_ key: String = defaultKey, to data: Data?) -> Data? {
        guard var entries = bindings(in: data),
              !entries.contains(where: { $0["command"] as? String == command }) else { return nil }
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
