**New in 1.0.9:** ChatGPT voice no longer gets stuck on “Voice chat is already starting” when you say “stop listening” quickly or start chats back to back, and “Hey Claude” is caught faster when the recognizer briefly drops the “Hey”.

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
