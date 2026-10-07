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

func expectStrip(_ text: String, _ expected: String) {
    let got = SendPhrase.strip(text)
    check(got == expected, "strip(\"\(text)\") → \"\(got)\", expected \"\(expected)\"")
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

// Send phrase
check(SendPhrase.ends("fix the failing test send it"), "ends: plain")
check(SendPhrase.ends("Fix the failing test. Send it."), "ends: punctuated")
check(SendPhrase.ends("fix it and sent it"), "ends: sent it")
check(!SendPhrase.ends("send it to the API and log the response"), "ends: mid-sentence")
check(!SendPhrase.ends("fix the test"), "ends: absent")
expectStrip("Fix the failing test. Send it.", "Fix the failing test.")
expectStrip("fix the failing test send it", "fix the failing test")
expectStrip("fix the failing test, send it!", "fix the failing test")
expectStrip("Send it.", "")
expectStrip("Please send it to the API", "Please send it to the API")
expectStrip("No phrase here", "No phrase here")

if failures == 0 {
    print("matcher: all \(count) cases passed")
    exit(0)
} else {
    print("matcher: \(failures) of \(count) cases failed")
    exit(1)
}
