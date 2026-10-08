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
expectCommand("fix the failing test yes", utterance: "yes", "yes")
expectCommand("fix the failing test Yes.", utterance: "Yes.", "Yes.")
expectCommand("fix the failing test yeah", utterance: "yeah", nil)
expectCommand("fix the failing test yeah", utterance: "yeah", nudged: true, "yeah")
expectCommand("fix the failing test yes and also the lint", utterance: "yes and also the lint", nil)
expectCommand("fix the failing test yes and also the lint", utterance: "yes and also the lint", nudged: true, nil)

// Where the speech after a pause starts, and what that means for a send command.
func expectStart(_ previous: String, _ current: String, _ expected: Int) {
    let got = WakeMatcher.utteranceStart(previous: words(previous), current: words(current))
    check(got == expected, "utteranceStart(\"\(previous)\" → \"\(current)\") → \(got), expected \(expected)")
}

let dictated = "Check WiFi is still not accepting my command after I say yes and I wanted to send the chat"
expectStart("", "Yes", 0)
expectStart(dictated, dictated + " yes", 19)
expectStart(dictated, "Yes", 0) // macOS starts the transcript over after a pause
expectStart("Yes I want you to fix the tests", "Yes", 0)
expectStart("fix the failing test", "fix the failing tests", 4) // re-heard its last word
expectStart("fix the failing test", "fix the failing tests yes", 4)
expectStart("fix the failing test", "and also the lint", 0)
expectStart("okay", "enter", 0)
expectStart("and also", "and press", 0)

func expectReply(_ previous: String, _ current: String, nudged: Bool = true, _ expected: String?) {
    let all = words(current)
    let utterance = Array(all.dropFirst(WakeMatcher.utteranceStart(previous: words(previous), current: all)))
    let got = SendPhrase.command(words: all, utterance: utterance, nudged: nudged)
    check(got == expected.map(words), "reply \"\(current)\" after \"\(previous)\" → \(got?.joined(separator: " ") ?? "nil"), expected \(expected ?? "nil")")
}

expectReply(dictated, "Yes", "yes")
expectReply(dictated, "Yes", nudged: false, "yes")
expectReply(dictated, "yeah", "yeah")
expectReply(dictated, dictated + " yes", "yes")
expectReply(dictated, "enter", "enter")
expectReply(dictated, "and also fix the lint", nil)
expectReply(dictated, "and then press enter", nil)

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
check(StopPhrase.isWhole(words("stop listening")), "stop whole: alone")
check(StopPhrase.isWhole(words("hang up")), "stop whole: hang up alone")
check(!StopPhrase.isWhole(words("and then hang up")), "stop whole: end of a sentence")

// The recognizer rewrote "Hey" (or "Hey Chad") into a transcript without the greeting
func rewrite(_ previous: String, _ current: String, _ expected: WakeTarget?, mayContinue: Bool = false) {
    let got = WakeMatcher.matchAfterRewrite(previous: previous, current: current)
    check(got?.target == expected && (got?.mayContinue ?? false) == mayContinue,
          "rewrite \"\(previous)\" → \"\(current)\": got \(got?.target.rawValue ?? "nothing"), expected \(expected?.rawValue ?? "nothing")")
}
rewrite("Hey", "Claude", .claude, mayContinue: true)
rewrite("Hey", "Claude code", .claudeCode)
rewrite("Hey Chad", "Chatty", .chatgpt)
rewrite("Hey", "Chatty Chad", .chatgpt)
rewrite("Hey", "Codex", .codex)
rewrite("Hello", "Claude", nil)
rewrite("", "Claude", nil)
rewrite("Hey", "Hey Claude", nil)          // has its own greeting; the normal match handles it
rewrite("I told her hey", "nothing", nil)
rewrite("Hey Claude", "Hey Claude code", nil)
rewrite("what a nice day", "Claude", nil)  // no greeting before
rewrite("hey there friend", "Claude", nil) // greeting too far back

// A run of partial transcripts from one recognition task, as the listener sees them
func partials(_ texts: [String], _ expected: WakeTarget?, mayContinue: Bool = false) {
    var carry = GreetingCarry()
    var previous = "", got: WakeMatch?
    for text in texts {
        got = WakeMatcher.match(text) ?? carry.match(previous: previous, current: text)
        previous = text
    }
    check(got?.target == expected && (got?.mayContinue ?? false) == mayContinue,
          "partials \(texts) → \(got?.target.rawValue ?? "nothing")\(got?.mayContinue == true ? " (may continue)" : ""), expected \(expected?.rawValue ?? "nothing")")
}
partials(["Hey", "Claude"], .claude, mayContinue: true)
partials(["Hey", "Claude", "Claude code"], .claudeCode)
partials(["Hey", "Claude", "Claude Code"], .claudeCode)
partials(["Hey Chad", "Chatty"], .chatgpt)
partials(["Hey", "Claude", "Claude is"], .claude)
partials(["Hey Claude", "Hey Claude code"], .claudeCode)
partials(["so", "Claude", "Claude code"], nil)

// Waiting for "code" after "hey claude"
let t0 = Date()
func hold(_ now: Double, changed: Double, spoke: Double, _ expected: Bool, _ name: String) {
    let got = ContinuationHold.keepWaiting(now: t0.addingTimeInterval(now), heldSince: t0,
                                           changedAt: t0.addingTimeInterval(changed), lastSpeechAt: t0.addingTimeInterval(spoke))
    check(got == expected, "hold: \(name) → \(got ? "wait" : "fire"), expected \(expected ? "wait" : "fire")")
}
hold(0.5, changed: 0, spoke: -0.1, false, "silence after hey claude")
hold(0.5, changed: 0, spoke: 0.1, false, "tail of claude right after the transcript")
hold(0.5, changed: 0, spoke: 0.4, true, "still talking: code on its way")
hold(1.6, changed: 0, spoke: 1.5, false, "never past the limit")
hold(0.9, changed: 0.6, spoke: 0.7, false, "transcript caught up with the speech")
hold(1.2, changed: 0, spoke: 0.4, false, "quiet long enough: nothing more is coming")
var activity = SpeechActivity()
_ = activity.isSpeech(level: -55)
check(!activity.isSpeech(level: -52), "speech: room noise isn't speech")
check(activity.isSpeech(level: -30), "speech: talking is")
check(!activity.isSpeech(level: -56), "speech: back to quiet")

// "stop listening" typed into the prompt by Claude's dictation
func stopTail(_ text: String, _ expected: String) {
    let got = String(text.dropLast(StopPhrase.trailingLength(text))).trimmingCharacters(in: .whitespacesAndNewlines)
    check(got == expected, "stop strip: \"\(text)\" → \"\(got)\", expected \"\(expected)\"")
}
stopTail("Add a dark mode toggle. Stop listening.", "Add a dark mode toggle.")
stopTail("Add a dark mode toggle stop listening", "Add a dark mode toggle")
stopTail("Stop listening.", "")
stopTail("Fix the login bug, stop listening", "Fix the login bug")
stopTail("Fix the login bug. Stop listing.", "Fix the login bug.")
stopTail("End the voice chat.", "")
stopTail("Add a dark mode toggle.", "Add a dark mode toggle.")
stopTail("Stop listening to the queue", "Stop listening to the queue")

// What the menu shows for a result
func menu(_ result: String, _ expected: String) {
    check(MenuText.forResult(result) == expected, "menu: \"\(result)\" → \"\(MenuText.forResult(result))\", expected \"\(expected)\"")
}
menu("ChatGPT: new chat + voice shortcut sent", "Opened ChatGPT voice")
menu("Codex: new chat + voice shortcut sent", "Opened Codex voice")
menu("Claude: voice mode started (second press)", "Opened Claude voice")
menu("Claude Code: sent (42 characters)", "Sent your prompt to Claude Code")
menu("ChatGPT: stopped listening", "Ended the ChatGPT voice chat")
menu("Claude: stopped listening", "Ended the Claude voice chat")
menu("Claude Code: stopped listening", "Stopped dictating to Claude Code. Nothing was sent.")
menu("Claude isn't installed", "Claude isn't installed")
menu("ChatGPT: already in a voice chat", "ChatGPT is already in a voice chat")
menu("ChatGPT: voice chat didn't start. If ChatGPT says it's already starting, quit and reopen ChatGPT.",
     "ChatGPT's voice chat didn't start. If it says it's already starting, quit and reopen ChatGPT.")

if failures == 0 {
    print("matcher: all \(count) cases passed")
    exit(0)
} else {
    print("matcher: \(failures) of \(count) cases failed")
    exit(1)
}
