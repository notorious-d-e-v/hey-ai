import Foundation

enum WakeTarget: String, CaseIterable {
    case chatgpt
    case codex
    case claude
    case claudeCode = "claude-code"

    var displayName: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .claudeCode: return "Claude Code"
        }
    }

    var wakePhrase: String {
        switch self {
        case .chatgpt: return "Hey Chatty"
        case .codex: return "Hey Codex"
        case .claude: return "Hey Claude"
        case .claudeCode: return "Hey Claude Code"
        }
    }
}

struct WakeMatch: Equatable {
    let target: WakeTarget
    let phrase: String
    /// "hey claude" was the last thing heard, so it may still become "hey claude code".
    var mayContinue = false
}

/// Finds the wake phrases in a live transcript. The recognizer often mishears short
/// names, so each name has a small set of known mishearings plus a fuzzy match. A
/// greeting word is required in front of the name so normal speech ("Claude said…",
/// "a cloud of smoke") never fires.
enum WakeMatcher {
    static let greetings: Set<String> = ["hey", "hay", "hei", "heh", "hi", "hej"]

    static let chattyWords: Set<String> = [
        "chatty", "chattie", "chatti", "chati", "chatie", "chattey", "chatey", "chaty",
        "shatty", "chetty", "chaddy",
    ]
    // "hey chat e" — the name split into two words.
    static let chattyHeads: Set<String> = ["chat", "chad", "shat", "chet"]
    static let chattyTails: Set<String> = ["e", "ee", "y", "ey", "ie", "t", "te", "tee", "tea", "ty", "tie"]

    static let codexWords: Set<String> = ["codex", "codecs", "codec", "kodex", "codexes"]
    // "hey code x"
    static let codexTails: Set<String> = ["x", "ex", "dex", "decks", "max"]

    static let claudeWords: Set<String> = [
        "claude", "claud", "clawed", "clawd", "cloud", "clod", "klaud", "klod", "clode", "claudes",
    ]
    static let codeWords: Set<String> = ["code", "codes", "coded", "coat", "coad", "kode"]

    static func match(_ transcript: String) -> WakeMatch? {
        let words = normalize(transcript)
        guard words.count >= 2 else { return nil }
        for i in 0..<(words.count - 1) where greetings.contains(words[i]) {
            let name = words[i + 1]
            let next = i + 2 < words.count ? words[i + 2] : nil
            let pair = "\(words[i]) \(name)"

            if isChatty(name) {
                return WakeMatch(target: .chatgpt, phrase: pair)
            }
            if let next, chattyHeads.contains(name), chattyTails.contains(next) {
                return WakeMatch(target: .chatgpt, phrase: "\(pair) \(next)")
            }
            if isCodex(name) {
                return WakeMatch(target: .codex, phrase: pair)
            }
            if let next, codeWords.contains(name), codexTails.contains(next) {
                return WakeMatch(target: .codex, phrase: "\(pair) \(next)")
            }
            if isClaude(name) {
                guard let next else { return WakeMatch(target: .claude, phrase: pair, mayContinue: true) }
                if codeWords.contains(next) {
                    return WakeMatch(target: .claudeCode, phrase: "\(pair) \(next)")
                }
                return WakeMatch(target: .claude, phrase: pair)
            }
        }
        return nil
    }

    static func isChatty(_ word: String) -> Bool {
        if chattyWords.contains(word) { return true }
        return word.count >= 4 && (word.hasPrefix("ch") || word.hasPrefix("sh"))
            && levenshtein(word, "chatty") <= 1
    }

    static func isCodex(_ word: String) -> Bool {
        if codexWords.contains(word) { return true }
        return word.count >= 5 && word.hasPrefix("co") && levenshtein(word, "codex") <= 1
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

/// "Send it" — said at the end of a Claude Code dictation to send the prompt.
enum SendPhrase {
    static let endings: [[String]] = [["send", "it"], ["sent", "it"], ["send", "that"]]

    /// True when the transcript ends with the send phrase.
    static func ends(_ transcript: String) -> Bool {
        let words = WakeMatcher.normalize(transcript)
        return endings.contains { words.count >= $0.count && Array(words.suffix($0.count)) == $0 }
    }

    private static let trailingPattern = try? NSRegularExpression(
        pattern: #"[\s,;:–—-]*\b(send it|sent it|send that)\b[\s.!?…]*$"#, options: [.caseInsensitive])

    /// How many characters at the end of dictated text are the send phrase (with the
    /// punctuation and spaces around it); 0 when it doesn't end with one.
    static func trailingLength(_ text: String) -> Int {
        guard let regex = trailingPattern,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return 0 }
        return text[range].count
    }

    /// Dictated text with a trailing "send it" removed.
    static func strip(_ text: String) -> String {
        String(text.dropLast(trailingLength(text))).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
