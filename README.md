# HeyVoice

A menu-bar Mac app that is always listening for four wake phrases:

| Say | It opens |
| --- | --- |
| **"Hey Chatty"** | ChatGPT, in a new standalone voice chat (no project folder) |
| **"Hey Codex"** | Codex, in a new voice chat in your current folder |
| **"Hey Claude"** | Claude, in a new chat with voice mode on |
| **"Hey Claude Code"** | A new Claude Code session in the desktop app's Code tab, with dictation on |

Claude Code has no back-and-forth voice mode, only dictation. Speak your prompt, then send it any of these ways:

- **End with "send it"** (or "send that", "send the message"). It sends after about a second of quiet.
- **Pause, then say one word on its own**: "enter", "send", "submit" or "done" ("that's it" and "go ahead" work too). It has to be its own utterance, so a prompt ending "…and press enter" doesn't send.
- **Answer the nudge.** After 2 seconds of quiet, a small "Done?" bubble appears above the prompt box with a soft tick. A plain "yes", "yeah" or "okay" then sends. If you keep talking, the bubble hides and dictation carries on.
- **Let Claude stop listening.** When Claude's dictation turns itself off, or you click its mic button, HeyVoice sends whatever is in the prompt box.

HeyVoice stops dictation, deletes the spoken command from the prompt, and presses Return. A pause by itself never sends.

Say **"stop listening"** (or "end voice chat", "end the call", "hang up") to end whatever is listening right away, without waiting for the app to wind down. HeyVoice presses Claude's Stop button, presses ⌃⇧V again in the ChatGPT app (it starts or stops voice), or stops a Claude Code dictation without sending it. The phrase has to end what you said, so "hang up the laundry" does nothing.

Wake phrases are ignored while Claude or the ChatGPT app is already using the microphone (a voice chat or dictation is open), so talking to an assistant can't open a second one. HeyVoice checks this with Core Audio, which reports every process that is capturing input.

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

- **ChatGPT and Codex** both use the ChatGPT + Codex app (`ChatGPT.app`). ChatGPT Classic no longer has a voice button: its `chatgpt://new-voice-conversation` link opens the app without starting voice. HeyVoice brings the app forward and opens a new chat, then presses ⌃⇧V, the app's own "start voice chat" shortcut. "Hey Chatty" opens the chat with ⌘⌥O ("New standalone chat", no project folder); "Hey Codex" uses ⌘N ("New Chat" in the current folder).
- **Claude**: HeyVoice opens `claude://claude.ai/new`, then presses the composer's **Use voice mode** button through Accessibility. Older claude.ai builds left that button unnamed; for those, HeyVoice falls back to the rightmost unnamed button in the composer's bottom row. It confirms voice mode started when the button stops offering "Use voice mode".
- **Claude Code**: HeyVoice opens `claude://code/new` (a new session in the folder Claude used last), then presses ⌘D, Claude's "toggle dictation" shortcut. If ⌘D doesn't start recording, it clicks the mic button instead. While you dictate, wake phrases are ignored, so words in your prompt can't open anything.

## Menu

- **Pause / Resume Listening**: turns the microphone off and on.
- **Send Now / Don't Send**: shown while a Claude Code dictation is open.
- **Test**: run any of the four actions without speaking, or write Claude's on-screen controls to the log. That dump is how to fix the Claude button lookup if Claude changes its page.
- **Launch at Login**: on means HeyVoice starts in the background whenever you log in. `open heyvoice://login/on` (or `off`) does the same from the terminal.
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

- **Locked screen.** HeyVoice keeps listening while the screen is locked or asleep, but macOS sends simulated key presses and clicks to the lock screen, not to apps. Steps that use them (ChatGPT's ⌘N/⌘⌥O and ⌃⇧V, Claude Code's ⌘D) can't work until you unlock. The log marks events that happened while the screen was locked. After a restart, nothing runs until you log in.
- The microphone is open the whole time, so the orange mic dot stays on.
- If AirPods are your input device, macOS switches them to call-quality audio while any app holds the mic. Use the Mac's built-in mic as the input to avoid this.
- Each app step depends on that app's current links, shortcuts and page layout. If either app changes, the Test menu and the log show which step failed.
- Mishearings are handled with a list of near-misses ("chati", "cloud", "clawed", …) in `Sources/WakeMatcher.swift`. Add to it if your voice gets misheard. `./build.sh` runs the matcher tests.
