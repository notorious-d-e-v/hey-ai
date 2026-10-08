# Hey AI launch kit

Everything needed to put Hey AI in front of people. All copy follows [`brand/BRAND.md`](../brand/BRAND.md): plain words, real phrases, no hype.

## The one-liners

Lead with “Hey Chatty”: ChatGPT is the assistant most people know. Say what it opens right after, since the nickname isn't obvious on its own.

- **Tagline:** Say “Hey Chatty”. ChatGPT opens, ready to talk.
- **One sentence:** Hey AI is a free Mac menu-bar app that opens ChatGPT, Codex, Claude or Claude Code in voice mode when you say its name.
- **GitHub About (≤ 350 chars):** Say “Hey Chatty”, “Hey Codex”, “Hey Claude” or “Hey Claude Code” and that assistant opens on your Mac, voice already on. On-device speech, nothing recorded. One-line install.
- **GitHub topics:** `macos` `menu-bar-app` `wake-word` `voice-assistant` `chatgpt` `codex` `claude` `claude-code` `speech-recognition` `swift`
- **GitHub website field:** https://notorious-d-e-v.github.io/hey-ai/
- **Social preview image:** [`brand/readme/social-preview.png`](../brand/readme/social-preview.png) (Settings → General → Social preview)

## The demo video (the most important asset)

Recorded 2026-10-08: **[`docs/demo.mp4`](../docs/demo.mp4)** (53 s, 1920×1248, captions burned in, −16 LUFS), on the site at [notorious-d-e-v.github.io/hey-ai/#demo](https://notorious-d-e-v.github.io/hey-ai/#demo). The README shows [`brand/readme/demo.gif`](../brand/readme/demo.gif), the “Hey Chatty” part, linking to it.

The cut, in order:
1. “Siri and Alexa are taking way too long to become smart. So let's just do this instead.”
2. The menu, then “Hey Chatty”. ChatGPT's voice pill appears on the desktop. “What's the capital of Indonesia?” “Jakarta.” “Thanks. Stop listening.”
3. “Hey Claude”, the same question, Claude answers. “stop listening.”
4. “Hey Claude Code”, then “Can you go ahead and ship dark mode for Hey AI?”. The *Done?* bubble appears, “yes”, and the prompt sends.

Captions follow the brand: what you say to Hey AI sits in a Highlight pill, and assistant replies are labeled with the assistant's name. X autoplays muted, so they carry the video without sound. Upload `docs/demo.mp4` to X directly (it's under X's 512 MB and 2:20 limits).

## X post (for @notorious_d_e_v)

Lead with the video. Pick one:

**Proof-led (recommended)**

> “hey chatty” and chatgpt is listening about a second later. no clicking
>
> also works for claude, codex and claude code
>
> free mac app, open source, one line to install
> notorious-d-e-v.github.io/hey-ai/?ref=x

**Shortest**

> i made my mac answer to “hey chatty”
>
> chatgpt opens with voice on. free, open source, one curl
> notorious-d-e-v.github.io/hey-ai/?ref=x

**Sharper**

> siri still can't open the one app i actually talk to all day
>
> so now i say “hey chatty” and chatgpt opens with voice on. “hey claude” for claude
>
> notorious-d-e-v.github.io/hey-ai/?ref=x

**Meme**

> me at 2am saying “hey claude code” to an empty room like it's a normal thing to do
>
> it opens a new session already dictating. “send it” sends the prompt

### Thread (if the first post lands)

1. *(video)* “hey chatty” and chatgpt is listening about a second later. no clicking. made it a free mac app
2. what you can say:
   “hey chatty” for chatgpt voice (chatty is easier to hear than “chatgpt”)
   “hey codex” for the same chatgpt voice chat, which can hand work to codex
   “hey claude” for claude voice
   “hey claude code” for a new session, already dictating
   “stop listening” hangs up whatever's open
3. claude code has no voice mode, only dictation. so you talk, say “send it”, and hey ai stops dictation, deletes “send it” from the prompt and hits enter. pause for 2 seconds and it asks if you're done. say “yes” and it sends
4. none of these apps have a “start voice” link. for chatgpt, hey ai presses chatgpt's own voice chat hotkey (it sets one up if you haven't), which works from any app. for claude it opens a new chat and presses the voice button
5. speech runs on-device through apple's recognizer. nothing is recorded, and no audio leaves your mac unless you turn on the online fallback (off by default). it also ignores wake words while an assistant already has the mic, so talking to chatgpt never opens a second one
6. install: `curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/install.sh | bash`
   github.com/notorious-d-e-v/hey-ai

Spend the first 30–60 minutes replying. Good replies to seed: which wake word people want next, what broke on their setup, the “why Chatty” question.

## Show HN

**Title:** Show HN: Hey AI – say “Hey Chatty” and ChatGPT opens in voice mode (macOS)

**Text:**

> I talk to ChatGPT and Claude a lot, and clicking around to get into voice mode every time felt silly, so I made a small menu-bar app that listens for a wake phrase and opens the assistant with voice already on.
>
> “Hey Chatty” starts a ChatGPT voice chat (“Hey Codex” starts the same one; its voice agent can hand work to Codex), “Hey Claude” opens Claude's voice mode, and “Hey Claude Code” starts a new Claude Code session already dictating. Say “send it”, or pause and say “yes”, and it sends the prompt. “Stop listening” ends whatever is open. (Chatty because “Hey ChatGPT” is a mouthful and gets misheard.)
>
> How it works: Apple's on-device speech recognizer listens for the phrases (nothing is recorded). None of these apps has a “start voice” URL. ChatGPT has a global Voice Chat hotkey with no default, so Hey AI sets one (⌃⌥⌘V, one entry in ~/.codex/keybindings.json, unless you already picked one) and presses it; it starts and stops voice from any app. Bringing ChatGPT forward and pressing its in-app shortcut was the first version, and it lost key presses whenever macOS was slow to switch apps. For Claude, it opens claude://claude.ai/new and presses the composer's voice button through the Accessibility API. Claude Code has only dictation, so it opens claude://code/new, toggles dictation with ⌘D, and strips “send it” before pressing Return. Key presses meant for an app first check that the app is frontmost. Core Audio's per-process state does the rest: wake phrases are ignored while an assistant already has the mic, and “stop listening” said over an assistant that's still talking (its voice reaches the mic too) stops it right away.
>
> Timing, from the demo recording: about a second from the end of the phrase to ChatGPT, Claude or Claude Code listening (the voice chat itself starts about 0.4 s after Hey AI recognizes the phrase). Listening costs about 3% of one core on an M4 Pro, nearly all of it Apple's recognizer.
>
> Caveats: the app is ad-hoc signed and not notarized yet; releases are built by GitHub Actions with a build attestation. It can't do anything while the Mac is locked. The first time, ChatGPT needs one restart to pick up the voice hotkey (Hey AI offers to do it).
>
> It's Swift, built with just the Command Line Tools, MIT licensed. Install is one curl line, or build from source. Happy to hear what breaks.
>
> https://github.com/notorious-d-e-v/hey-ai

## Product Hunt

- **Name:** Hey AI
- **Tagline (≤ 60):** Say “Hey Chatty” and ChatGPT opens, ready to talk
- **Description:** A free Mac menu-bar app. Say an assistant's name (ChatGPT, Codex, Claude or Claude Code) and it opens with voice already on. Speech is recognized on your Mac, nothing is recorded, and setup is one window.
- **Gallery:** the demo video, the light banner, the setup window ([`tools/snapshot.sh`](../tools/snapshot.sh) renders it), the brand sheet.

## Measuring the launch

Two sources, neither of which touches the app (it sends nothing):

- **GitHub**: installs (downloads of `Hey-AI.zip`, one per `curl … | bash`), stars, issues, repo visitors and referrers. GitHub keeps traffic for only 14 days, so `scripts/stats.py` saves a snapshot every morning to `~/workspace/hey-ai-stats` (`scripts/install-stats-job.sh` installs the daily job). Run `python3 scripts/stats.py --report` for the summary.
- **The site**: [GoatCounter](https://heyai.goatcounter.com) counts visits, referrers and three events with no cookies: `install-copied` (the Copy button), `click-download-app` and `click-read-script`.

Link with a channel tag so the site can split visitors by where they came from:

| Where | Link |
| --- | --- |
| X | `https://notorious-d-e-v.github.io/hey-ai/?ref=x` |
| Show HN | `https://github.com/notorious-d-e-v/hey-ai` (HN prefers the repo; GitHub shows it as news.ycombinator.com) |
| Product Hunt | `https://notorious-d-e-v.github.io/hey-ai/?ref=producthunt` |
| Anywhere else | `?ref=<name>` on the site link |

What to watch:

- **Launch week, daily:** installs against unique visitors (site plus repo), Copy clicks against site visitors, referrers by channel, stars, and any issue about setup or a wake phrase not working. The app has no telemetry, so issues are the only window into whether first runs succeed.
- **After launch, weekly:** new installs per week once the spike fades, stars per week, new issues per 100 installs (bugs vs feature requests), which wake words people ask for, and how many existing users download each new release.

## Before launch checklist

- [ ] Repo is public at `github.com/notorious-d-e-v/hey-ai` with the About text, topics and social preview set.
- [ ] Release `v1.0.0` exists with `Hey-AI.zip`, `Hey-AI.zip.sha256` and an attestation: push the tag (`git tag v1.0.0 && git push origin v1.0.0`) and the Release workflow builds and publishes it.
- [ ] The install line works on a Mac that has never had Hey AI.
- [ ] GitHub Pages is on (Settings → Pages → `main` / `docs`) and the site loads.
- [x] Demo video recorded and embedded in the README (`brand/readme/demo.gif` → `docs/demo.mp4`).
- [ ] GoatCounter account created with the site code `heyai` (the site already sends to heyai.goatcounter.com).
- [ ] Optional: a short domain (for example `heyai.sh`) pointing at the install script, so the command becomes `curl -fsSL heyai.sh | bash`.
