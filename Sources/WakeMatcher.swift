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

    /// The recognizer sometimes shows "Hey", then rewrites its transcript as just "Claude"
    /// and only offers "Hey Claude" again a couple of seconds later. When the last
    /// transcript ended in a greeting (or a greeting and one more word, as in "Hey Chad")
    /// and the new one replaces it rather than adding to it, this is the greeting it lost.
    static func droppedGreeting(previous: String, current: String) -> String? {
        let before = normalize(previous), now = normalize(current)
        guard let first = now.first, !greetings.contains(first), !now.starts(with: before) else { return nil }
        return before.suffix(2).last(where: { greetings.contains($0) })
    }

    static func matchAfterRewrite(previous: String, current: String) -> WakeMatch? {
        droppedGreeting(previous: previous, current: current).flatMap { match("\($0) \(current)") }
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

    /// Where the speech after a pause starts in the recognizer's new transcript. Usually the
    /// transcript grows (maybe re-hearing its last word) and the new words follow the old
    /// ones; but after a pause it can also start over with only the new speech, "Yes".
    static func utteranceStart(previous: [String], current: [String]) -> Int {
        let shared = zip(previous, current).prefix { $0 == $1 }.count
        // A short transcript has to be kept whole, or "and also" → "and press enter" would
        // look like it grew by "press enter".
        let kept = previous.count >= 3 ? previous.count - 1 : previous.count
        if current.count >= previous.count && shared >= kept { return previous.count }
        return 0
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

/// How you tell Hey AI a Claude Code dictation is finished.
enum SendPhrase {
    /// Send whenever they end what you said: "…fix the bug, send it".
    static let anywhere = phrases(["send it", "sent it", "send that", "send message", "send the message"])
    /// Send only when said on their own after a pause, so "…and press enter" can't fire.
    static let standalone = phrases([
        "yes", "enter", "send", "submit", "done", "i'm done", "press enter", "hit enter", "go ahead",
        "that's it", "that's all",
    ])
    /// Answers to the "Done?" nudge. They can also lead a phrase: "yes, send it".
    static let answers = phrases(["yes", "yeah", "yep", "yup", "ok", "okay", "sure", "yes please"])
        .sorted { $0.count > $1.count }

    private static func phrases(_ list: [String]) -> [[String]] { list.map(WakeMatcher.normalize) }

    /// The words that make up a send command at the end of what was heard, or nil.
    /// - words: everything heard since dictation started
    /// - utterance: the words since the last pause
    /// - nudged: the utterance began after the "Done?" nudge appeared
    static func command(words: [String], utterance: [String], nudged: Bool) -> [String]? {
        if !utterance.isEmpty {
            if standalone.contains(utterance) || anywhere.contains(utterance) { return utterance }
            let answer = answers.first { utterance.starts(with: $0) } ?? []
            let rest = Array(utterance.dropFirst(answer.count))
            if !rest.isEmpty && (anywhere.contains(rest) || standalone.contains(rest)) { return utterance }
            if nudged && rest.isEmpty && !answer.isEmpty { return utterance }
        }
        return anywhere.first { words.count >= $0.count && Array(words.suffix($0.count)) == $0 }
    }

    /// How many characters at the end of the dictated text are the spoken command (plus the
    /// spaces and commas before it); 0 when the text doesn't end with it. Close spellings
    /// count ("Inter." for "enter"), since Claude's dictation hears words its own way.
    /// `looser` allows two letters off in words of 7 or more letters ("listing" for "listening").
    static func trailingLength(_ text: String, command: [String], looser: Bool = false) -> Int {
        guard !command.isEmpty, let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}']+"#) else { return 0 }
        let tokens = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
        guard tokens.count >= command.count else { return 0 }
        let tail = Array(tokens.suffix(command.count))
        for (range, expected) in zip(tail, command) {
            let word = WakeMatcher.normalize(String(text[range])).joined()
            let allowed = looser && expected.count >= 7 ? 2 : (expected.count >= 4 ? 1 : 0)
            guard word == expected || (allowed > 0 && WakeMatcher.levenshtein(word, expected) <= allowed) else {
                return 0
            }
        }
        guard text[tail.last!.upperBound...].allSatisfy({ $0.isWhitespace || ".!?…".contains($0) }) else { return 0 }
        var start = tail.first!.lowerBound
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isWhitespace || ",;:–—-".contains(text[previous]) else { break }
            start = previous
        }
        return text.distance(from: start, to: text.endIndex)
    }

    /// Dictated text with the spoken command removed.
    static func strip(_ text: String, command: [String]) -> String {
        String(text.dropLast(trailingLength(text, command: command))).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// "Stop listening" — ends whichever voice chat or dictation is open.
enum StopPhrase {
    static let phrases: [[String]] = [
        "stop listening", "stop voice mode", "stop voice chat", "end voice mode", "end voice chat",
        "end the voice chat", "end the chat", "end chat", "end the call", "end call", "hang up",
    ].map(WakeMatcher.normalize)

    /// True when what was heard ends with a stop phrase.
    static func ends(_ transcript: String) -> Bool {
        let words = WakeMatcher.normalize(transcript)
        return phrases.contains { words.count >= $0.count && Array(words.suffix($0.count)) == $0 }
    }

    /// True when an utterance is nothing but a stop phrase. Used while dictating, so a
    /// prompt that happens to end "…then hang up" doesn't stop it.
    static func isWhole(_ utterance: [String]) -> Bool {
        phrases.contains(utterance)
    }

    /// How many characters at the end of dictated text are a stop phrase (the longest one
    /// that fits), so it can be deleted from the prompt; 0 if it doesn't end with one.
    static func trailingLength(_ text: String) -> Int {
        phrases.map { SendPhrase.trailingLength(text, command: $0, looser: true) }.max() ?? 0
    }
}

/// Catches a wake phrase whose greeting the recognizer rewrote away ("Hey" → "Claude"),
/// and keeps that greeting for the rest of the phrase, so "Claude" growing into "Claude
/// code" still reads as "hey claude code". One per recognition task.
struct GreetingCarry {
    private(set) var greeting: String?

    mutating func match(previous: String, current: String) -> WakeMatch? {
        if let greeting, let carried = WakeMatcher.match("\(greeting) \(current)") { return carried }
        guard let dropped = WakeMatcher.droppedGreeting(previous: previous, current: current),
              let match = WakeMatcher.match("\(dropped) \(current)") else { return nil }
        greeting = dropped
        return match
    }
}

/// Tells speech from background noise in the microphone level: anything 10 dB over a
/// noise floor that drops at once and creeps up slowly (so a few seconds of talking don't
/// raise it much).
struct SpeechActivity {
    private(set) var noiseFloor: Float?

    /// Feed one audio buffer's level in dBFS; true if it sounds like someone talking.
    mutating func isSpeech(level: Float) -> Bool {
        guard let floor = noiseFloor else { noiseFloor = level; return false }
        noiseFloor = level < floor ? level : floor + (level - floor) * 0.005
        return level > floor + 10
    }
}

/// "hey claude" waits a moment in case "code" follows. The recognizer can deliver "code"
/// late, so keep waiting while there's been speech since the transcript last changed: more
/// words are on their way. A bare "Hey Claude" followed by silence isn't slowed down.
enum ContinuationHold {
    /// Transcript unchanged this long with nothing more said: it was just "hey claude".
    static let wait: TimeInterval = 0.5
    /// Speech this long after the last transcript change counts as another word coming.
    static let speechMargin: TimeInterval = 0.15
    /// Once it's been quiet this long, whatever was said should be in the transcript.
    static let settled: TimeInterval = 0.6
    /// Never hold longer than this in all.
    static let limit: TimeInterval = 1.5

    static func keepWaiting(now: Date, heldSince: Date, changedAt: Date, lastSpeechAt: Date) -> Bool {
        now.timeIntervalSince(heldSince) < limit
            && lastSpeechAt.timeIntervalSince(changedAt) > speechMargin
            && now.timeIntervalSince(lastSpeechAt) < settled
    }
}
