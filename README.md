# HeyVoice

A menu-bar Mac app that is always listening for four wake phrases:

| Say | It opens |
| --- | --- |
| **"Hey Chatty"** | ChatGPT (ChatGPT Classic), in a new voice conversation |
| **"Hey Codex"** | The ChatGPT + Codex app (`ChatGPT.app`), in a new voice chat |
| **"Hey Claude"** | Claude, in a new chat with voice mode on |
| **"Hey Claude Code"** | A new Claude Code session in the desktop app's Code tab, with dictation on |

Claude Code has no back-and-forth voice mode, only dictation. Speak your prompt, then end with **"send it"**. HeyVoice waits for about a second of quiet after "send it", then stops dictation, deletes "send it" from the prompt, and presses Return. A pause alone never sends; with no "send it", HeyVoice stops waiting after 90 seconds of silence or 5 minutes, and the prompt stays unsent.

Wake-phrase detection uses Apple's on-device speech recognizer, so audio never leaves the Mac. Nothing you say is logged. The log only records wake events and errors.

## Build and run

```bash
./build.sh
open build/HeyVoice.app
```

Only the Command Line Tools are needed, not Xcode. A waveform icon appears in the menu bar.

On first launch, macOS asks for three permissions:

1. **Microphone**: to hear the wake phrase.
2. **Speech Recognition**: to turn audio into text on this Mac.
3. **Accessibility**: to press the voice shortcuts and buttons in Codex, Claude and Claude Code. Enable HeyVoice under System Settings → Privacy & Security → Accessibility.

`build.sh` signs the app ad-hoc with a requirement of just its bundle identifier, so the permissions carry over to rebuilt copies.

## How each app is opened

- **ChatGPT**: HeyVoice opens ChatGPT Classic's `chatgpt://new-voice-conversation` link. It starts the app first if it isn't running, because the link can get lost while the app is launching.
- **Codex**: HeyVoice brings the ChatGPT + Codex app forward, presses ⌘N for a new chat, then ⌃⇧V, which is the app's own "start voice chat" shortcut.
- **Claude**: HeyVoice opens `claude://claude.ai/new`, then presses the composer's **Use voice mode** button through Accessibility. Older claude.ai builds left that button unnamed; for those, HeyVoice falls back to the rightmost unnamed button in the composer's bottom row. It confirms voice mode started when the button stops offering "Use voice mode".
- **Claude Code**: HeyVoice opens `claude://code/new` (a new session in the folder Claude used last), then presses ⌘D, Claude's "toggle dictation" shortcut. If ⌘D doesn't start recording, it clicks the mic button instead. While you dictate, wake phrases are ignored, so words in your prompt can't open anything.

## Menu

- **Pause / Resume Listening**: turns the microphone off and on.
- **Send Now / Stop Waiting for "Send It"**: shown while a Claude Code dictation is open.
- **Test**: run any of the four actions without speaking, or write Claude's on-screen controls to the log. That dump is how to fix the Claude button lookup if Claude changes its page.
- **Launch at Login**.
- **Allow Online Speech Recognition**: off by default. It only matters when on-device recognition is unavailable, and it sends microphone audio to Apple.

You can also run the actions from the terminal while HeyVoice is running:

```bash
open heyvoice://open/chatgpt
```

```bash
open heyvoice://open/claude-code
```

```bash
open heyvoice://send/claude-code
```

`open/` also takes `codex` and `claude`.

```bash
open heyvoice://dump/claude
```

Log: `~/Library/Logs/HeyVoice/heyvoice.log`

## Known limits

- The microphone is open the whole time, so the orange mic dot stays on.
- If AirPods are your input device, macOS switches them to call-quality audio while any app holds the mic. Use the Mac's built-in mic as the input to avoid this.
- Each app step depends on that app's current links, shortcuts and page layout. If either app changes, the Test menu and the log show which step failed.
- Mishearings are handled with a list of near-misses ("chati", "cloud", "clawed", …) in `Sources/WakeMatcher.swift`. Add to it if your voice gets misheard. `./build.sh` runs the matcher tests.
