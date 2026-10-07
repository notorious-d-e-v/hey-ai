import Foundation

// Runs the wake-phrase and send-phrase matchers against known transcripts. Built and run
// by build.sh.

var failures = 0
var count = 0

func check(_ ok: Bool, _ message: @autoclosure () -> String) {
    count += 1
    if !ok {
        failures += 1
        print("FAIL  \(message())")
    }
}

func expect(_ transcript: String, _ expected: WakeTarget?, mayContinue: Bool = false) {
    let got = WakeMatcher.match(transcript)
    check(got?.target == expected && (got?.mayContinue ?? false) == mayContinue,
          "\"\(transcript)\" → \(got?.target.rawValue ?? "nothing")\(got?.mayContinue == true ? " (may continue)" : ""), expected \(expected?.rawValue ?? "nothing")\(mayContinue ? " (may continue)" : "")")
}

// ChatGPT
expect("Hey Chatty", .chatgpt)
expect("hey, chatty!", .chatgpt)
expect("Hey Chati what's up", .chatgpt)
expect("Hey chattie", .chatgpt)
expect("hey shatty", .chatgpt)
expect("Hey chat e", .chatgpt)
expect("Hey chat tea", .chatgpt)
expect("Hi Chatty", .chatgpt)
expect("so then I said hey chatty", .chatgpt)
expect("Hey Chatty's", .chatgpt)

// Codex
expect("Hey Codex", .codex)
expect("hey codecs", .codex)
expect("Hey code x", .codex)
expect("hey Codex, open the repo", .codex)

// Claude
expect("Hey Claude", .claude, mayContinue: true)
expect("Hey, Claude.", .claude, mayContinue: true)
expect("hey cloud", .claude, mayContinue: true)
expect("Hey clawed", .claude, mayContinue: true)
expect("hey claud can you help", .claude)
expect("Hay Claude what's the weather", .claude)
expect("ok so hey Claude", .claude, mayContinue: true)

// Claude Code
expect("Hey Claude Code", .claudeCode)
expect("hey cloud code", .claudeCode)
expect("Hey Claude code, fix the failing test", .claudeCode)
expect("hey clawed codes", .claudeCode)

// Nothing
expect("", nil)
expect("hey", nil)
expect("Claude is great", nil)
expect("Claude Code is great", nil)
expect("the chatty kids next door", nil)
expect("the codex of laws", nil)
expect("hey there", nil)
expect("hey chat", nil)
expect("hey chat I need help", nil)
expect("hey code", nil)
expect("a cloud of smoke", nil)
expect("hey chatting with friends", nil)
expect("hey Chad", nil)
expect("hey clouds", nil)
expect("hey catty", nil)

// Send commands
func words(_ text: String) -> [String] { WakeMatcher.normalize(text) }

func expectCommand(_ heard: String, utterance: String? = nil, nudged: Bool = false, _ expected: String?) {
    let got = SendPhrase.command(words: words(heard), utterance: words(utterance ?? heard), nudged: nudged)
    check(got == expected.map(words), "command(\"\(heard)\", utterance: \"\(utterance ?? heard)\", nudged: \(nudged)) → \(got?.joined(separator: " ") ?? "nil"), expected \(expected ?? "nil")")
}

expectCommand("fix the failing test send it", "send it")
expectCommand("Fix the failing test. Send it.", "send it")
expectCommand("fix it and sent it", "sent it")
expectCommand("fix the test", nil)
expectCommand("send it to the API and log the response", nil)
expectCommand("fix the failing test enter", utterance: "enter", "enter")
expectCommand("fix the failing test submit", utterance: "submit", "submit")
expectCommand("fix the failing test that's it", utterance: "that's it", "that's it")
expectCommand("fix the failing test okay enter", utterance: "okay enter", "okay enter")
expectCommand("fix the failing test yes send it", utterance: "yes send it", "yes send it")
expectCommand("and then press enter", nil)
expectCommand("and then press enter", utterance: "and then press enter", nil)
expectCommand("fix the failing test yes", utterance: "yes", nudged: true, "yes")
expectCommand("fix the failing test yes", utterance: "yes", nil)
expectCommand("fix the failing test yes and also the lint", utterance: "yes and also the lint", nudged: true, nil)

func expectStrip(_ text: String, _ command: String, _ expected: String) {
    let got = SendPhrase.strip(text, command: words(command))
    check(got == expected, "strip(\"\(text)\", \"\(command)\") → \"\(got)\", expected \"\(expected)\"")
}

expectStrip("Fix the failing test. Send it.", "send it", "Fix the failing test.")
expectStrip("fix the failing test send it", "send it", "fix the failing test")
expectStrip("fix the failing test, send it!", "send it", "fix the failing test")
expectStrip("Fix the failing test. Enter.", "enter", "Fix the failing test.")
expectStrip("Fix the failing test. Inter.", "enter", "Fix the failing test.")
expectStrip("Fix the failing test. Yes, send it.", "yes send it", "Fix the failing test.")
expectStrip("Fix the failing test. That's it.", "that's it", "Fix the failing test.")
expectStrip("Send it.", "send it", "")
expectStrip("Please send it to the API", "send it", "Please send it to the API")
expectStrip("Press enter to continue", "enter", "Press enter to continue")
expectStrip("No command here", "enter", "No command here")

// Stop phrases
check(StopPhrase.ends("stop listening"), "stop: plain")
check(StopPhrase.ends("OK thanks, stop listening."), "stop: after other words")
check(StopPhrase.ends("hang up"), "stop: hang up")
check(StopPhrase.ends("great, end the call"), "stop: end the call")
check(!StopPhrase.ends("hang up the laundry"), "stop: hang up mid-sentence")
check(!StopPhrase.ends("stop listening to that podcast"), "stop: stop listening mid-sentence")
check(!StopPhrase.ends("stop"), "stop: bare stop")

if failures == 0 {
    print("matcher: all \(count) cases passed")
    exit(0)
} else {
    print("matcher: \(failures) of \(count) cases failed")
    exit(1)
}
