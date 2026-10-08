**New in 1.0.15:** “Hey Chatty” is much more reliable. Hey AI now uses ChatGPT's own Voice Chat hotkey, which starts and stops a voice chat from any app, so ChatGPT no longer has to come to the front first. That was the step that kept failing, and stopping a chat early could leave ChatGPT stuck. If you already set that hotkey in ChatGPT, Hey AI uses yours. Otherwise it sets it to ⌃⌥⌘V and offers to restart ChatGPT once so ChatGPT picks it up. “Hey Codex” now starts the same voice chat. When Claude's voice button needs a second press, voice now starts about 1.5 s sooner.

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
