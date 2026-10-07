import Foundation

enum WakeTarget: String {
    case chatgpt
    case claude

    var displayName: String { self == .chatgpt ? "ChatGPT" : "Claude" }
}

struct WakeMatch: Equatable {
    let target: WakeTarget
    let phrase: String
}

/// Finds "hey chatty" / "hey claude" in a live transcript. The recognizer often mishears
/// short names, so each name has a small set of known mishearings plus a fuzzy match.
/// A greeting word is required in front of the name so normal speech ("Claude said…",
/// "a cloud of smoke") never fires.
enum WakeMatcher {
    static let greetings: Set<String> = ["hey", "hay", "hei", "heh", "hi", "hej"]

    static let chattyWords: Set<String> = [
        "chatty", "chattie", "chatti", "chati", "chatie", "chattey", "chatey", "chaty",
        "shatty", "chetty", "chaddy", "chatty's",
    ]
    // "hey chat e" — the name split into two words.
    static let chattyHeads: Set<String> = ["chat", "chad", "shat", "chet"]
    static let chattyTails: Set<String> = ["e", "ee", "y", "ey", "ie", "t", "te", "tee", "tea", "ty", "tie"]

    static let claudeWords: Set<String> = [
        "claude", "claud", "clawed", "clawd", "cloud", "clod", "klaud", "klod", "clode", "claudes",
    ]

    static func match(_ transcript: String) -> WakeMatch? {
        let words = normalize(transcript)
        guard words.count >= 2 else { return nil }
        for i in 0..<(words.count - 1) where greetings.contains(words[i]) {
            let name = words[i + 1]
            if isChatty(name) {
                return WakeMatch(target: .chatgpt, phrase: "\(words[i]) \(name)")
            }
            if i + 2 < words.count, chattyHeads.contains(name), chattyTails.contains(words[i + 2]) {
                return WakeMatch(target: .chatgpt, phrase: "\(words[i]) \(name) \(words[i + 2])")
            }
            if isClaude(name) {
                return WakeMatch(target: .claude, phrase: "\(words[i]) \(name)")
            }
        }
        return nil
    }

    static func isChatty(_ word: String) -> Bool {
        if chattyWords.contains(word) { return true }
        return word.count >= 4 && (word.hasPrefix("ch") || word.hasPrefix("sh"))
            && levenshtein(word, "chatty") <= 1
    }

    static func isClaude(_ word: String) -> Bool {
        if claudeWords.contains(word) { return true }
        return word.count >= 4 && word.hasPrefix("cl") && levenshtein(word, "claude") <= 1
    }

    /// Lowercase words with punctuation removed and a trailing possessive dropped.
    static func normalize(_ text: String) -> [String] {
        let cleaned = String(text.lowercased().map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " })
        return cleaned.split(separator: " ").map { word in
            var w = String(word)
            if w.hasSuffix("'s") { w.removeLast(2) }
            return w.replacingOccurrences(of: "'", with: "")
        }.filter { !$0.isEmpty }
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
