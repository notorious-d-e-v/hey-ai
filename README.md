# HeyVoice

A menu-bar Mac app that is always listening for two wake phrases:

| Say | It opens |
| --- | --- |
| **"Hey Chatty"** | ChatGPT, in a new voice chat |
| **"Hey Claude"** | Claude, in a new chat with voice mode on |

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
3. **Accessibility**: to press ChatGPT's voice shortcut and Claude's voice button. Enable HeyVoice under System Settings → Privacy & Security → Accessibility.

`build.sh` signs the app ad-hoc with a requirement of just its bundle identifier, so the permissions carry over to rebuilt copies.

## How each app is opened

- **ChatGPT** (the current ChatGPT + Codex app): HeyVoice brings the app forward, presses ⌘N for a new chat, then ⌃⇧V, which is ChatGPT's own "start voice chat" shortcut.
- **ChatGPT Classic** (pick it under *"Hey Chatty" Opens*): HeyVoice opens the app's `chatgpt://new-voice-conversation` link.
- **Claude**: HeyVoice opens `claude://claude.ai/new`, then presses the composer's **Use voice mode** button through Accessibility. Older claude.ai builds left that button unnamed; for those, HeyVoice falls back to the rightmost unnamed button in the composer's bottom row. It confirms voice mode started when the button stops offering "Use voice mode".

## Menu

- **Pause / Resume Listening**: turns the microphone off and on.
- **"Hey Chatty" Opens**: choose ChatGPT or ChatGPT Classic.
- **Test**: run either action without speaking, or write Claude's on-screen controls to the log. That dump is how to fix the Claude button lookup if Claude changes its page.
- **Launch at Login**.
- **Allow Online Speech Recognition**: off by default. It only matters when on-device recognition is unavailable, and it sends microphone audio to Apple.

You can also run the actions from the terminal while HeyVoice is running:

```bash
open heyvoice://open/chatgpt
```

```bash
open heyvoice://open/claude
```

```bash
open heyvoice://dump/claude
```

Log: `~/Library/Logs/HeyVoice/heyvoice.log`

## Known limits

- The microphone is open the whole time, so the orange mic dot stays on.
- If AirPods are your input device, macOS switches them to call-quality audio while any app holds the mic. Use the Mac's built-in mic as the input to avoid this.
- The ChatGPT and Claude steps depend on those apps' current shortcuts and page layout. If either app changes, the Test menu and the log show which step failed.
- Mishearings are handled with a list of near-misses ("chati", "cloud", "clawed", …) in `Sources/WakeMatcher.swift`. Add to it if your voice gets misheard. `./build.sh` runs the matcher tests.
