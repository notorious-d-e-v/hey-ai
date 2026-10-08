**New in 1.0.16:** “stop listening” works right away even while ChatGPT or Claude is still talking. Before, the assistant's own voice could hold it up for several seconds, long enough for it to hear “stop listening” and answer.

Say an assistant's name and it opens, ready to talk.

- **“Hey Chatty”** starts a new ChatGPT voice chat, right where you are.
- **“Hey Codex”** starts the same voice chat. ChatGPT's voice agent can hand work to Codex.
- **“Hey Claude”** opens Claude in voice mode.
- **“Hey Claude Code”** opens a new Claude Code session, already dictating. Finish with “send it”, or pause and say “enter”.
- **“Stop listening”** ends whatever voice chat is open.

Install:

```bash
curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/install.sh | bash
```

macOS 14 or later, Apple silicon or Intel. Speech is recognized on your Mac and never recorded.
