**New in 1.0.11:** “Hey Claude Code” is told apart from “Hey Claude” more reliably: if you're still talking when the recognizer is slow to deliver “Code”, Hey AI waits for it. And “stop listening” presses Claude's Stop button again if Claude ignored the first press.

Say an assistant's name and it opens, ready to talk.

- **“Hey Chatty”** opens a new ChatGPT voice chat.
- **“Hey Codex”** opens a new Codex voice chat in your project.
- **“Hey Claude”** opens Claude in voice mode.
- **“Hey Claude Code”** opens a new Claude Code session, already dictating. Finish with “send it”, or pause and say “enter”.
- **“Stop listening”** ends whatever voice chat is open.

Install:

```bash
curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/install.sh | bash
```

macOS 14 or later, Apple silicon or Intel. Speech is recognized on your Mac and never recorded.
