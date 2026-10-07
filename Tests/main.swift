import Foundation

// Runs the wake-phrase matcher against known transcripts. Built and run by build.sh.

var failures = 0
var count = 0

func expect(_ transcript: String, _ expected: WakeTarget?) {
    count += 1
    let got = WakeMatcher.match(transcript)?.target
    if got != expected {
        failures += 1
        print("FAIL  \"\(transcript)\" → \(got?.rawValue ?? "nothing"), expected \(expected?.rawValue ?? "nothing")")
    }
}

// Should open ChatGPT
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

// Should open Claude
expect("Hey Claude", .claude)
expect("Hey, Claude.", .claude)
expect("hey cloud", .claude)
expect("Hey clawed", .claude)
expect("hey claud can you help", .claude)
expect("Hay Claude", .claude)
expect("ok so hey Claude", .claude)

// Should do nothing
expect("", nil)
expect("hey", nil)
expect("Claude is great", nil)
expect("the chatty kids next door", nil)
expect("hey there", nil)
expect("hey chat", nil)
expect("hey chat I need help", nil)
expect("a cloud of smoke", nil)
expect("hey chatting with friends", nil)
expect("hey Chad", nil)
expect("hey clouds", nil)
expect("hey catty", nil)

if failures == 0 {
    print("matcher: all \(count) cases passed")
    exit(0)
} else {
    print("matcher: \(failures) of \(count) cases failed")
    exit(1)
}
