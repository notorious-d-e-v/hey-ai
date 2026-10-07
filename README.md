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

You need macOS 14 or later (Apple silicon or Intel) and the [Claude](https://claude.ai/download) desktop app and/or the current [ChatGPT](https://openai.com/chatgpt/download/) desktop app (the one with Codex built in). The older ChatGPT app has no voice mode Hey AI can start.

<p align="center"><img src="brand/readme/setup-ready.png" alt="The Hey AI setup window after the three permissions are allowed, listing the wake phrases" width="420"></p>

<details>
<summary>Download it yourself instead</summary>

Get `Hey-AI.zip` from [Releases](https://github.com/notorious-d-e-v/hey-ai/releases/latest), unzip it and drag **Hey AI** to Applications. Hey AI isn't notarized by Apple yet, so the first time you open it macOS says it can't check it. Open **System Settings → Privacy & Security** and click **Open Anyway**. (Files downloaded with `curl` aren't marked as downloaded, so the installer doesn't hit this check. That's a convenience, not a security feature. See [Security](#security).)

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
- If Claude ends the dictation itself (its own timeout, or you click its mic button), Hey AI sends what's there.

Hey AI removes the spoken command from the prompt before pressing Return. A pause on its own doesn't send unless Claude ends the dictation. If you switch to another app before it sends, it stops and sends nothing.

## Privacy

- **Your voice stays on your Mac.** Hey AI uses Apple's on-device speech recognition and never records audio.
- **It only acts on names.** Everything else it hears is discarded once it's checked.
- **The log is short.** `~/Library/Logs/HeyAI/heyai.log` records which phrase was heard and what was opened. Diagnostic dumps list only the buttons around the prompt box, never typed or dictated text or chat titles. Still, read it before you attach it to a public issue.
- **You'll see the orange microphone dot** while it listens. Pause it from the menu bar any time. Listening costs about 3% of one CPU core and 150 MB of memory on an M4 Pro, nearly all of it Apple's speech recognizer.
- **No network, no analytics.** Hey AI makes no network requests of its own. (The menu has an *Allow Online Speech Recognition* fallback, off by default, for Macs without on-device speech. It sends audio to Apple, so leave it off unless you need it.)

## Permissions

| Permission | Why Hey AI needs it |
| --- | --- |
| Microphone | To hear the wake phrase. |
| Speech Recognition | To turn speech into text, on your Mac. |
| Accessibility | Claude and ChatGPT have no “start voice” link. After a wake phrase, Hey AI opens a new chat and presses Claude's voice button, or sends the app's own shortcut (⌃⇧V in ChatGPT, ⌘D in Claude Code). |

The setup window asks for all three in one pass. macOS doesn't let apps switch Accessibility on themselves, so you flip one switch in the list it opens, which needs an administrator's password.

Accessibility is a broad permission: it would let an app read and control any window. Hey AI only acts on Claude and ChatGPT, only after a wake phrase, and checks that the app is still in front before every key press or click. All of it is in [`Sources/Launcher.swift`](Sources/Launcher.swift).

## Menu

Click the quote mark in the menu bar to pause listening, run any action without speaking (Test), open setup again or choose whether it starts at login.

**Keep Screen Awake** stops the display from sleeping, so your Mac doesn't lock on its own and wake phrases keep working while you step away. It also means an unattended Mac stays unlocked, so only turn it on where that's fine.

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
- **It doesn't work while my Mac is locked.** macOS doesn't let any app drive other apps behind the lock screen. **Keep Screen Awake** stops the display from sleeping so the Mac doesn't lock on its own, which leaves an unattended Mac unlocked.
- **My AirPods sound worse.** While any app holds an AirPods microphone, macOS switches them to call-quality audio. Pick your Mac's built-in microphone as the input.

</details>

## Security

- **The installer** is [`install.sh`](install.sh). It downloads the latest release zip, refuses to continue if the release's SHA-256 file is missing or doesn't match, moves the app to Applications and opens it. Read it before piping it to `bash`, or download the app yourself.
- **Releases are built by GitHub Actions** from a tagged commit ([workflow](.github/workflows/release.yml)), with a build attestation you can check: `gh attestation verify Hey-AI.zip -R notorious-d-e-v/hey-ai`.
- **The app is signed ad hoc, not with an Apple Developer ID**, and isn't notarized yet. Its code signature requires only the bundle identifier, so updates keep the permissions you granted. The trade-off is that another ad-hoc-signed app using the same identifier could inherit them. A Developer ID signature will replace this.
- **Build it yourself** if you'd rather trust only source: see below.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/uninstall.sh | bash
```

It removes the app, its settings, logs and permissions, and its login item (if Hey AI is running when you uninstall; otherwise it tells you where to remove it).

## Build from source

You only need Apple's Command Line Tools (`xcode-select --install`), not Xcode.

```bash
git clone https://github.com/notorious-d-e-v/hey-ai.git && cd hey-ai && ./build.sh && open "build/Hey AI.app"
```

`./build.sh` runs the phrase tests, then builds a universal app. `./scripts/release.sh` makes the release zip.

---

Hey AI is free and open source under the [MIT license](LICENSE). Brand guidelines are in [`brand/BRAND.md`](brand/BRAND.md).

Claude and Claude Code are trademarks of Anthropic. ChatGPT and Codex are trademarks of OpenAI. Hey AI is an independent project, not affiliated with or endorsed by either company.
