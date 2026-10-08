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

A real 15-second screen recording beats any graphic. Record it with ⌘⇧5 and **turn the microphone on** in Options so people hear the phrase.

1. Start on a clean desktop with the Hey AI quote mark visible in the menu bar.
2. Say “Hey Chatty”. ChatGPT opens a new voice chat. Ask one short question and let it answer for a couple of seconds.
3. Say “stop listening”. The voice chat ends.
4. Say “Hey Claude Code”, dictate “add a dark mode toggle to the settings page”, pause until the *Done?* bubble appears, then say “yes”. The prompt sends.
5. End on the menu-bar icon. No talking head, no music, no text overlays beyond the phrase being said.

Export as MP4 (for X and the README) and a ≤ 10 MB GIF of steps 1–2 (for places that don't autoplay video). Put the MP4 in a GitHub issue comment or release to get a CDN link, then embed it at the top of the README under the banner.

Worth recording a second cut with “Hey Claude” in step 2, for places where Claude users gather (Claude subreddits, Anthropic-focused threads).

## X post (for @notorious_d_e_v)

Lead with the video. Pick one:

**Proof-led (recommended)**

> “hey chatty” and chatgpt opens in voice mode. a second or two, no clicking
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

1. *(video)* “hey chatty” and chatgpt opens in voice mode. a second or two, no clicking. made it a free mac app
2. what you can say:
   “hey chatty” for chatgpt voice (chatty is easier to hear than “chatgpt”)
   “hey codex” for codex voice
   “hey claude” for claude voice
   “hey claude code” for a new session, already dictating
   “stop listening” hangs up whatever's open
3. claude code has no voice mode, only dictation. so you talk, say “send it”, and hey ai stops dictation, deletes “send it” from the prompt and hits enter. pause for 2 seconds and it asks if you're done. say “yes” and it sends
4. none of these apps have a “start voice” link. so hey ai opens a new chat, then sends chatgpt's own voice shortcut or presses claude's voice button. it checks the app is still in front before every key press
5. speech runs on-device through apple's recognizer. nothing is recorded, and no audio leaves your mac unless you turn on the online fallback (off by default). it also ignores wake words while an assistant already has the mic, so talking to chatgpt never opens a second one
6. install: `curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/install.sh | bash`
   github.com/notorious-d-e-v/hey-ai

Spend the first 30–60 minutes replying. Good replies to seed: which wake word people want next, what broke on their setup, the “why Chatty” question.

## Show HN

**Title:** Show HN: Hey AI – say “Hey Chatty” and ChatGPT opens in voice mode (macOS)

**Text:**

> I talk to ChatGPT and Claude a lot, and clicking around to get into voice mode every time felt silly, so I made a small menu-bar app that listens for a wake phrase and opens the assistant with voice already on.
>
> “Hey Chatty” and “Hey Codex” open ChatGPT's and Codex's voice chats, “Hey Claude” opens Claude's voice mode, and “Hey Claude Code” starts a new Claude Code session already dictating. Say “send it” and it sends the prompt. “Stop listening” ends whatever is open. (Chatty because “Hey ChatGPT” is a mouthful and gets misheard.)
>
> How it works: Apple's on-device speech recognizer listens for the phrases (nothing is recorded). None of these apps has a “start voice” URL. For ChatGPT and Codex, Hey AI brings the app forward and sends the app's own shortcuts (new chat, then ⌃⇧V for voice). For Claude, it opens claude://claude.ai/new and presses the composer's voice button through the Accessibility API. Claude Code has only dictation, so it opens claude://code/new, toggles dictation with Claude's ⌘D shortcut, and strips “send it” before pressing Return. Every synthetic key press first checks the target app is still frontmost. It also reads Core Audio's per-process input state and ignores wake phrases while an assistant already has the mic.
>
> Timing: ChatGPT and Codex are talking one to two seconds after you finish the phrase when the app is already open; Claude's voice mode is usually live in about a second. Listening costs about 3% of one core on an M4 Pro, nearly all of it Apple's recognizer.
>
> Caveats: the app is ad-hoc signed and not notarized yet; releases are built by GitHub Actions with a build attestation. It can't do anything while the Mac is locked.
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
- [ ] Demo video recorded and embedded in the README.
- [ ] GoatCounter account created with the site code `heyai` (the site already sends to heyai.goatcounter.com).
- [ ] Optional: a short domain (for example `heyai.sh`) pointing at the install script, so the command becomes `curl -fsSL heyai.sh | bash`.
