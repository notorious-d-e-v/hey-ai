<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/readme/banner-dark.png">
    <img src="brand/readme/banner-light.png" alt="Hey AI. Say “Hey Claude” and Claude opens, ready to talk." width="100%">
  </picture>
</p>

**Say an assistant's name and it opens, ready to talk.** Hey AI is a tiny Mac menu-bar app that listens for *“Hey Claude”*, *“Hey Chatty”*, *“Hey Codex”* and *“Hey Claude Code”*, and opens that assistant with voice already on. Speech is recognized on your Mac, and nothing is recorded.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/install.sh | bash
```

Paste it into Terminal. About five seconds later Hey AI is in Applications and its setup window is open. Allow three permissions there, then say **“Hey Claude”**.

You need macOS 14 or later (Apple silicon or Intel) and the [Claude](https://claude.ai/download) and/or [ChatGPT](https://openai.com/chatgpt/download/) desktop app.

<details>
<summary>Download it yourself instead</summary>

Get `Hey-AI.zip` from [Releases](https://github.com/notorious-d-e-v/hey-ai/releases/latest), unzip it and drag **Hey AI** to Applications. Hey AI isn't notarized by Apple yet, so the first time you open it macOS says it can't check it. Open **System Settings → Privacy & Security** and click **Open Anyway**. The one-line installer skips this step, because files downloaded with `curl` aren't flagged.

</details>

## What you can say

| Say | What happens |
| --- | --- |
| **“Hey Claude”** | Claude opens a new chat in voice mode. |
| **“Hey Claude Code”** | A new Claude Code session opens in the Claude app, already dictating. Finish with **“send it”**, or pause and say **“enter”**. |
| **“Hey Chatty”** | ChatGPT opens a new voice chat. |
| **“Hey Codex”** | Codex opens a new voice chat in your current project. |
| **“Stop listening”** | Ends whatever voice chat is open, right away. |

While Claude or ChatGPT is already listening, Hey AI ignores wake phrases, so talking to your assistant never opens a second one.

### Sending a Claude Code prompt

Claude Code has dictation rather than a voice conversation, so you speak your prompt and then send it:

- End with **“send it”** (or “send that”). It sends after a second of quiet.
- Or pause, then say **“enter”**, “send” or “done” on its own. A prompt that ends “…and press enter” won't send.
- Pause for two seconds and a small bubble asks *Done?* A plain **“yes”** sends.
- If Claude stops dictating on its own, or you click its mic button, Hey AI sends what's there.

Hey AI removes the spoken command from the prompt before pressing Return. A pause on its own never sends.

## Privacy

- **Your voice stays on your Mac.** Hey AI uses Apple's on-device speech recognition and never records audio.
- **It only acts on names.** Everything else it hears is discarded once it's checked.
- **The log is short.** `~/Library/Logs/HeyAI/heyai.log` records which phrase was heard and what was opened, never what you said to your assistant.
- **No network, no analytics.** Hey AI makes no network requests of its own. (The menu has an *Allow Online Speech Recognition* fallback, off by default, for Macs without on-device speech. It sends audio to Apple, so leave it off unless you need it.)

## Permissions

| Permission | Why Hey AI needs it |
| --- | --- |
| Microphone | To hear the wake phrase. |
| Speech Recognition | To turn speech into text, on your Mac. |
| Accessibility | Claude and ChatGPT have no “start voice” link, so Hey AI opens a new chat and presses the voice button for you, the way you would. |

The setup window asks for all three in one pass. macOS doesn't let apps switch Accessibility on themselves, so you flip one switch in the list it opens.

## Menu

Click the quote mark in the menu bar to pause listening, run any action without speaking (Test), open setup again, start at login, or turn on **Keep Screen Awake**.

<details>
<summary>How it works</summary>

- **Listening.** `SFSpeechRecognizer` in on-device mode runs over the microphone. Recognition restarts every 50 seconds and after each wake phrase, so an old phrase can never fire twice. Common mishearings are accepted (“chati”, “cloud”, “clawed”, “codecs”). See [`Sources/WakeMatcher.swift`](Sources/WakeMatcher.swift).
- **Claude.** Opens `claude://claude.ai/new`, then presses the composer's *Use voice mode* button through Accessibility.
- **Claude Code.** Opens `claude://code/new`, then presses ⌘D, Claude's dictation shortcut.
- **ChatGPT and Codex.** Brings the ChatGPT app forward, opens a new chat (⌘⌥O for a standalone chat, ⌘N for one in your project), then presses ⌃⇧V, the app's own voice shortcut.
- **Already listening?** Core Audio reports which processes are using the microphone. If Claude or ChatGPT is, wake phrases are ignored.

</details>

<details>
<summary>Troubleshooting</summary>

- **Nothing happens when I talk.** The menu should say *Listening (on-device)*. If it says on-device speech isn't available, turn on Dictation in **System Settings → Keyboard** so macOS downloads it.
- **The app opens but voice doesn't start.** Check that Hey AI is switched on under **System Settings → Privacy & Security → Accessibility**. If it is, Claude or ChatGPT may have changed its layout. Choose **Test → Write Claude Controls to Log** and open an issue with the log.
- **It doesn't work while my Mac is locked.** macOS doesn't let any app drive other apps behind the lock screen. **Keep Screen Awake** stops the display from sleeping, so the Mac doesn't lock on its own.
- **My AirPods sound worse.** While any app holds an AirPods microphone, macOS switches them to call-quality audio. Pick your Mac's built-in microphone as the input.

</details>

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/uninstall.sh | bash
```

It removes the app, its login item, settings, logs and permissions.

## Build from source

You only need Apple's Command Line Tools (`xcode-select --install`), not Xcode.

```bash
git clone https://github.com/notorious-d-e-v/hey-ai.git && cd hey-ai && ./build.sh && open "build/Hey AI.app"
```

`./build.sh` runs the phrase tests, then builds a universal app. `./scripts/release.sh` makes the release zip.

---

Hey AI is free and open source under the [MIT license](LICENSE). Brand guidelines are in [`brand/BRAND.md`](brand/BRAND.md).

Claude and Claude Code are trademarks of Anthropic. ChatGPT and Codex are trademarks of OpenAI. Hey AI is an independent project, not affiliated with or endorsed by either company.
