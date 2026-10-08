**New in 1.0.12:** saying “stop listening” while dictating to Claude Code no longer leaves “stop listening” typed in the prompt; Hey AI deletes it after dictation stops.

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
