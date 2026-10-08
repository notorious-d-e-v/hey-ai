import Foundation

/// What the menu says happened. The log keeps the detailed wording for debugging; the
/// menu says it in plain words. Problems pass through as they are, since they already
/// say what went wrong.
enum MenuText {
    static func forResult(_ result: String) -> String {
        for name in ["ChatGPT", "Codex"] where result == "\(name): new chat + voice shortcut sent" {
            return "Opened \(name) voice"
        }
        switch result {
        case _ where result.hasSuffix("quit and reopen ChatGPT."):
            return "ChatGPT's voice chat didn't start. If it says it's already starting, quit and reopen ChatGPT."
        case _ where result.hasSuffix(": already in a voice chat"):
            return "\(result.prefix { $0 != ":" }) is already in a voice chat"
        case _ where result.hasPrefix("Claude: voice mode started"): return "Opened Claude voice"
        case _ where result.hasPrefix("Claude: pressed the voice button"): return "Opened Claude and pressed its voice button"
        case _ where result.hasPrefix("Claude Code: dictating"): return "Dictating to Claude Code"
        case _ where result.hasPrefix("Claude Code: sent"): return "Sent your prompt to Claude Code"
        case _ where result.hasPrefix("Claude Code: pressed Return"): return "Pressed Return in Claude Code"
        case "Claude Code: stopped dictating (prompt not sent)", "Claude Code: stopped listening":
            return "Stopped dictating to Claude Code. Nothing was sent."
        case "Claude Code: nothing was dictated, so nothing was sent": return "Nothing was dictated, so nothing was sent to Claude Code"
        case "Claude Code: stopped waiting for a send command after 10 minutes": return "Stopped waiting to send to Claude Code after 10 minutes"
        case _ where result.hasSuffix(": stopped listening"):
            return "Ended the \(result.prefix { $0 != ":" }) voice chat"
        default: return result
        }
    }
}
