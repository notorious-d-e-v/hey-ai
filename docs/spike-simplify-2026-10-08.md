# Spike: the simplest reliable Hey AI (2026-10-08)

Branch `spike/simplify-wake-words`. Research, measurements and a live-tested prototype. Nothing is merged or released, and installed Hey AI is still 1.0.14.

**Owner decisions (10-08):**

1. Turn the hotkey on automatically. Use the hotkey you set if there is one; otherwise set it up and ask to restart ChatGPT, and if you don't restart, say it kicks in at the next restart.
2. "Hey Chatty" doesn't need to bring ChatGPT forward.
3. Keep "Hey Codex" as an alias.
4. Live-test the prototype, then open a draft PR.

## Executive brief

**The problem.** Most of the "it keeps messing up" reports are about "Hey Chatty", and the wake word itself is rarely the cause. Hey AI starts ChatGPT's voice chat with a keyboard shortcut (⌃⇧V). ChatGPT only reacts to it when its own window has keyboard focus, so Hey AI must first bring ChatGPT to the front and then press the keys quickly. Two things go wrong:

1. **The key press never arrives.** While you are using the Mac, macOS often delays or refuses Hey AI's request to bring ChatGPT forward. Sometimes ChatGPT comes forward but the key still doesn't reach it.
2. **ChatGPT gets stuck.** A voice chat stopped while it is still starting can leave ChatGPT refusing every new voice chat ("Voice chat is already starting") until it is restarted.

Releases 1.0.9 to 1.0.14 each added waits, timers or guards around these two problems.

**What changes.** ChatGPT has a better way in: an optional, system-wide **Voice Chat hotkey**. It starts or stops a voice chat without bringing ChatGPT to the front. Pressed while a chat is still starting, it cancels cleanly, and it even clears the stuck state. Hey AI can turn this hotkey on for users by adding one entry to ChatGPT's settings file (`~/.codex/keybindings.json`). It takes effect the next time ChatGPT starts.

**Why it matters.** In today's measurements the hotkey started voice 35 out of 35 times, typically 0.36 s after the press, and stopped it every time in about 0.07 s. The current method, used while the Mac was in use, got ChatGPT listening within 1.5 s only 18 out of 36 times. Switching lets us delete most of the ChatGPT timing code. Claude needs only small cleanups, and the wake-word listening is sound and mostly stays.

## How this was measured

- **Hey AI's log**: `~/Library/Logs/HeyAI/heyai.log`, 10-07 to 10-08, 1,168 lines.
- **ChatGPT's own records** serve as ground truth for "did a voice chat start":
  - each voice chat creates a `voice_chat` thread in `~/.codex/state_5.sqlite`;
  - its rollout file has `realtime_session_started` and `realtime_session_closed` events;
  - ChatGPT's desktop log (`~/Library/Logs/com.openai.codex/<date>/codex-desktop-*.log`) records each start, refusal and error.
- **Code reading** of ChatGPT 26.1002.52244 (`app.asar`: the main-process `avatar-overlay-realtime` controller and the renderer's voice command handlers).
- **Scripted live trials** (11:37–12:03Z), 115 runs. A temporary, uncommitted harness inside a debug build of Hey AI did the following:
  - set up a starting state: ChatGPT in front, Finder in front, ChatGPT hidden, or a full-screen app;
  - started voice by one of the methods below, timed until ChatGPT held the microphone (Core Audio per-process input), held the chat 0.3–3 s, then stopped it.

  Each run was checked afterwards against ChatGPT's thread table and desktop log. ChatGPT was never quit by the harness. The harness is described here so it can be rebuilt, and per the test rules it was never committed.

## 1. What actually went wrong today

| Time (UTC) | Said | Hey AI logged | ChatGPT logged | Cause |
| --- | --- | --- | --- | --- |
| 11:13:37, 11:14:13 | Hey Chatty | "still connecting" after 2.2 s, then "didn't start" | Nothing: no thread, no start, no refusal | ⌃⇧V never reached ChatGPT's page, although Hey AI saw ChatGPT in front |
| 11:18:06 | Hey Codex | front after 5.6 s, then "didn't start" | New ChatGPT process at 11:18:09 | ChatGPT was relaunching |
| 11:25:07, 11:25:35 | Hey Chatty | "didn't start" | Nothing (that process quit 11:25:45) | Press lost |
| 11:26:42 | Hey Chatty | "didn't start" (gave up after 15 s) | Start held for 17 s, then began at 11:26:59 | A start right after a ChatGPT launch waited for its voice window |
| 11:26:59 | Hey Chatty | worked; "stop listening" stopped it at 11:27:01.4 | Refused the new press ("already starting"), session 11:27:00.6, closed 11:27:01.5, **reconnected itself** 11:27:04, closed 11:27:14 | Stop landed 0.8 s after the session began |
| 11:27:21 to 11:41 | Hey Chatty, Hey Codex | "still connecting", then "didn't start" | `Voice chat is already starting` on every press (11:31:48, plus 6 of my trials) | **Stuck start lock** until the owner restarted ChatGPT |

My early-stop trials (below) did not reproduce the stuck lock: 0 reconnects in 74 chats. So the exact trigger is still uncertain. The ingredients match ChatGPT's code: a stop during start, a self-reconnect, and a start promise that never settles.

## 2. Must-keep edge cases (each one has happened)

| # | Edge case | Evidence | What handles it |
| --- | --- | --- | --- |
| 1 | The recognizer drops the greeting by rewriting "Hey" into "Claude" | 1.0.8 latency test: "Hey Claude" took 2.7 s instead of 0.8 s; regression in 1.0.10 | `GreetingCarry` |
| 2 | "code" arrives late after "hey claude" | Owner's 2 misses (1.0.11); every hold logs heard→press 0.53–0.56 s | 0.5 s hold, extended while the mic hears speech |
| 3 | Short names are misheard ("Chatty" becomes "Chad"), sometimes only right in an alternative | Matcher mishearing lists; after dictation, "Chatty" was heard as "Chad" until the task restarted (1.0.10) | Fuzzy matcher, runner-up transcripts, contextual strings, re-prime after dictation |
| 4 | After a pause the recognizer starts its transcript over, and short replies come back final | 1.0.7 replay: "…send the chat" became "Yes" in the same task | `utteranceStart`, `heardChanges` |
| 5 | A wake phrase while an assistant already has the mic | 2 "already listening; ignored" and 3 "already in a voice chat" | `MicActivity` guard |
| 6 | Screen locked: keys go to the lock screen | Today 11:51–11:53 (trials ran into it); ChatGPT's hotkey also ignores presses while locked | `Session.isScreenLocked` guard |
| 7 | Audio device changes | 18 "audio configuration changed" restarts | `restartEngine` |
| 8 | Timers must keep running while the menu is open | 1.0.8 | `.common` run-loop timers |
| 9 | **ChatGPT doesn't come to the front, or the key is lost** | Owner's 11:13:37 and 11:14:13; trials: 12 of 36 never front within 8 s while the Mac was in use | **Proposed: the Voice Chat hotkey (needs no front app)** |
| 10 | **ChatGPT's start lock gets stuck** | 11:27 to 11:41 today; 1.0.9 history | **Proposed: one hotkey press clears it (`resetSession`)** |
| 11 | ChatGPT takes the mic about 1.5 s before its session starts (median 1.5 s, max 2.4 s across 74 chats), and a ⌃⇧V stop in that window errors | 8 "interrupted before the session could start", all from ⌃⇧V stops (5 of them 3.1 s after the mic) | **Proposed: hotkey stop, which cancels cleanly (0 errors in 35, including at 0.3 s)** |
| 12 | Right after a ChatGPT launch or update, a start is slow (9–12 s) or lost | 11:18:06; 1.0.14 history | Don't press twice within ~10 s; say plainly it didn't start |
| 13 | Claude ignores the first press on "Use voice mode" | 7 of 25 starts needed a second press; a working first press is confirmed within 0.37 s (9 of 9) | Second press, after a **1 s** wait instead of 2.5 s |
| 14 | Claude ignores the first Stop right after voice starts | 1 time in about 20 stops | One retry |
| 15 | Claude Code: dictation types "send it" or "stop listening" into the prompt; dictation also ends on its own | 1.0.12; 3 sends after dictation ended on its own | Strip with verification; dictation watcher |
| 16 | "Stop listening" must not end your own dictation in the other assistant | 11:04:55 incident (1.0.14) | Prefer the assistant Hey AI opened |
| 17 | You switch apps mid-action: keys must not land elsewhere | 1 "you switched apps" | Frontmost check before every keystroke |

## 3. Mechanism audit

*Cost* is a rough feel for lines and moving parts. *Fires* is how often the log shows it doing anything.

### ChatGPT and Codex (`Launcher.startVoiceChat`, `endVoiceNow`, AppDelegate)

| Mechanism | Added | Why | Still needed? | Cost | Verdict |
| --- | --- | --- | --- | --- | --- |
| Bring ChatGPT forward, wait until frontmost (8 s, or 25 s cold) | 1.0.0 | ⌃⇧V needs focus | Only for the ⌃⇧V fallback. Activation is itself the main failure (case 9) | medium | **Delete for the hotkey path**; keep for the fallback |
| 0.05 s front delay (3 s when cold) | 1.0.13 | Speed | Works when idle (15 of 15); can't fix refused activation | small | Delete with the hotkey |
| ⌘⌥O "new standalone chat" when no window | 1.0.13 | ⌃⇧V needs a window | ChatGPT 26.1002's menus no longer have ⌘⌥O (File has New Chat ⌘N, New Temporary Chat ⇧⌘N) | small | **Delete** (dead) |
| Codex: ⌘N, then 0.4 s | 1.0.0 | Show a new Codex task | Cosmetic: voice is the same agent (`global_hotkey_new_thread`) either way | small | **Delete**, or open with a deep link (owner decision) |
| 2 s mic wait, plus a 15 s background watcher, `chatgptConnectingSince`, `Result.connecting`, `onChatGPTConnectFinished`, AppDelegate `chatgptStarts` | 1.0.14 | Don't press ⌃⇧V into a slow start; report late connects | The guard idea stays; the machinery doesn't | **large** (about 60 lines across 3 files) | **Replace with one timestamp** (`pendingSince`) |
| 2 s restart gap after a stop | 1.0.9 | A stopped chat winds down | Not needed for hotkey stops (they reset synchronously); not yet measured below 2.5 s | small | Delete with the hotkey (verify) |
| 2 s settle before a stop (`chatgptSettle`) | 1.0.14 | ⌃⇧V stop ignored in the mic-before-session gap | Gap is up to 2.4 s, so 2 s is too short (case 11). The hotkey cancels at any time | small | **Delete** for the hotkey; fallback settle 3 s |
| Stop while starting: `endChatGPTVoiceOnceStarted` | 1.0.9/1.0.14 | ⌃⇧V can't cancel a start | The hotkey cancels a start directly | medium | **Delete** |
| "Already in a voice chat" (mic check) | 1.0.9 | Don't start a second chat | **Yes**: the hotkey is a toggle, so pressing it would stop the chat | small | Keep |
| "Quit and reopen ChatGPT" message | 1.0.9 | Stuck lock | With the hotkey, saying "Hey Chatty" again clears it | small | Reword |
| `lastOpenedAssistant` preference in stop | 1.0.14 | Case 16 | Yes | small | Keep |

### Wake listening (`WakeListener`, `WakeMatcher`)

| Mechanism | Added | Still needed? | Verdict |
| --- | --- | --- | --- |
| On-device recognizer, task rotated every 50 s and after each wake | 1.0.0 | Yes (bounded transcripts; an old phrase can't fire twice) | Keep |
| Fuzzy matcher with mishearing lists, alternatives, contextual strings | 1.0.0 | Yes (case 3); 145 tests | Keep |
| 3 s cooldown after a wake | 1.0.0 | Yes | Keep |
| `GreetingCarry` and `droppedGreeting` | 1.0.9/1.0.10 | Yes (case 1). `WakeMatcher.matchAfterRewrite` is now used only by tests | Keep (optional: drop the wrapper) |
| 0.5 s hold for "code" | 1.0.0 | Yes (case 2) | Keep |
| Audio-aware hold extension (`SpeechActivity`, `ContinuationHold`, per-buffer RMS) | 1.0.11 | **0 extended holds logged** since it shipped (about 13 Claude tries). It fixes a real but rare miss | Keep for now; it logs when it fires. Replace with a fixed 0.7 s hold if still 0 after a week |
| Utterance split and restart detection, `isFinal` handling | 1.0.3/1.0.7 | Yes (case 4) | Keep |
| Done? bubble and nudge-only answers (yeah, ok, sure) | 1.0.3–1.0.5 | Feature the owner asked for; stable since 1.0.7 | Keep |
| Re-prime contextual strings after dictation | 1.0.10 | Yes | Keep |
| `.common` timers; engine restart on device change | 1.0.8, 1.0.0 | Yes (cases 7–8) | Keep |

### Claude and Claude Code (`Launcher`, `AXReader`)

| Mechanism | Fires | Verdict |
| --- | --- | --- |
| `claude://claude.ai/new`, find "Use voice mode" by label, press, confirm | 25 of 25 found | Keep |
| Fallback: rightmost *unlabeled* button (older claude.ai) | 0 of 18 (always 1 labeled candidate) | **Delete** |
| Confirm "started" when the buttons merely changed (`composer buttons after press`) | 0 | **Delete** |
| Second press after 2.5 s | 7 of 25 | Keep, **wait 1 s** (a working press shows in 0.37 s) |
| Stop button and one retry | 1 retry | Keep |
| ⌘D dictation, then a **mouse-click fallback** for start, stop and send (`Mouse.click` moves the pointer) | Start: 0 of 24. The stop and send fallbacks aren't logged | **Replace** with a second ⌘D (no pointer move) |
| `MicState` width fallback when the button has no pressed state | 0 (always `pressed=0/1`) | **Delete** |
| Send strip with verification; stop-phrase strip; dictation watcher; 10-min limit | used | Keep |

## 4. Design per target

### "Hey Chatty" and "Hey Codex": ChatGPT's Voice Chat hotkey

What the code does (ChatGPT 26.1002, main process):

- The hotkey is the `realtimeVoice` command, an OS-global shortcut with no default.
- Pressing it calls `toggleGlobalHotkeySession()`:
  - With no voice session reserved, it requests a start (`source: global_hotkey_new_thread`). That's exactly what ⌃⇧V asks for today, so it's the same voice agent and the same projectless `voice_chat` thread.
  - Otherwise it stops the active session, or cancels a start with `resetSession()` + `cancelStart`. `resetSession` clears the lock that causes "Voice chat is already starting".
- ⌃⇧V (`composer.startVoiceMode`) is different. It only exists in a focused ChatGPT page, refuses a start while one is in flight, and its stop (`controlActive`) is ignored until the session registers.
- ChatGPT reads `~/.codex/keybindings.json` (`[{"command": "realtimeVoice", "key": "Control+Alt+Command+V"}]`) at launch. Nothing watches the file. Changing the shortcut in ChatGPT's settings takes effect at once.
- A synthetic key press from Hey AI (letter keys; an F19 test combo did not fire) triggers another app's global hotkey. This was verified with a probe and then live with ChatGPT.

Simplest reliable flow:

```
Start ("Hey Chatty"):
  ChatGPT not installed               → say so
  ChatGPT has the mic                 → "already in a voice chat" (pressing would stop it)
  Hey AI pressed < 10 s ago, no mic   → "still starting" (pressing would cancel it)
  otherwise                           → press the hotkey; note the time (chatgptAskedAt); wait ≤ 2 s for the mic, then report
Stop ("stop listening", ChatGPT is the target):
  ChatGPT has the mic, or a start is pending → press the hotkey; wait ≤ 3 s for the mic to go
```

- **Turning it on** (at every launch, until it's done):
  - You set one in ChatGPT: Hey AI uses it. If it's a key Hey AI can't press (a function key, or a modifier on its own), Hey AI uses ⌃⇧V and logs why.
  - You removed it in ChatGPT's settings, or the file isn't one Hey AI can read: it's left alone, and Hey AI uses ⌃⇧V.
  - Otherwise Hey AI adds ⌃⌥⌘V, merging into any existing file. If ChatGPT is running, Hey AI asks to restart it: as a row in the setup window on first run, or as a one-time alert ("Restart ChatGPT" / "Later"). After Later, the menu says the hotkey kicks in the next time ChatGPT restarts. If ChatGPT isn't running, it picks the hotkey up when it opens.
- **When it's live**: a binding exists, and either you set it in ChatGPT or ChatGPT launched after Hey AI wrote it. Until then Hey AI uses the ⌃⇧V fallback.
- **Restart ChatGPT**: Hey AI quits ChatGPT, which may ask you to confirm, waits up to 30 s for it to exit, then opens it again. The alert warns that this ends anything ChatGPT is in the middle of.
- **Fallback when the hotkey isn't live**: today's ⌃⇧V path, trimmed. It brings ChatGPT forward, presses ⌃⇧V, waits up to 2 s for the mic, uses the same pending-start guard, and waits until 4 s after the start before a ⌃⇧V stop. There's no background watcher, no stop-once-started and no restart gap.
- **"Hey Codex"** (decided: alias): the same voice chat as "Hey Chatty". ChatGPT's agent can hand work to Codex.
- **Bring ChatGPT forward?** (decided: no): the voice window floats over the current app.

Risks: `keybindings.json` and the `realtimeVoice` id are undocumented (but so are ⌃⇧V and every Accessibility path). The combo could clash with another app's global shortcut; ChatGPT then logs "Unable to register voice chat hotkey", and Hey AI's fallback would need to read that line. Users get a system-wide ⌃⌥⌘V (a bonus).

### Which voice should "Hey Chatty" start? (the other session's question)

The ChatGPT/Codex mode switch in the sidebar is unrelated to the failures. ⌃⇧V has exactly one handler (the Codex realtime agent, `priority: "fallback"`) and starts it in either mode. ChatGPT mode does have its own voice (chatgpt.com's "wingman" voice, `sessionType: wm`). It starts from the ChatGPT composer's voice button, or when the page route has `?mode=voice`. I found no command id, menu item, keybinding or deep-link parameter that starts it:

- `codex://new?mode=work|chat|codex` only picks the app mode for a new thread, and in a live try it didn't switch a window that had a running Codex task.
- ChatGPT's web content wasn't exposed to Accessibility even after 8 s.
- Background clicks don't reach it.

Starting it would therefore need activation plus clicking, the exact fragile pattern this spike removes. I didn't take over the owner's screen to measure it. **Recommendation**: keep the Codex voice agent for "Hey Chatty" now. If you prefer plain ChatGPT voice, try it once by hand (ChatGPT mode, then the composer's voice button) and we can revisit if OpenAI adds a hotkey or link for it. The agent's "Thinking…" latency comes from its model and reasoning setting (ChatGPT itself suggests "Light" for faster voice replies), not from Hey AI.

### "Hey Claude"

Keep `claude://claude.ai/new`, the label lookup and the press. Wait 1 s, not 2.5 s, before the second press. Delete the unlabeled-button fallback and the "buttons changed" heuristic.

### "Hey Claude Code"

Keep ⌘D, the send phrases, the Done? bubble, the strips and the watcher. Delete the mouse-click fallbacks and the width-based mic state. It still needs Claude in front for keystrokes, which is a known limit. It isn't failing in the log (24 of 24 dictations started).

### "Stop listening"

1. Dictating: stop the dictation.
2. Otherwise, the assistant Hey AI opened last, if it has the mic (or, for ChatGPT, a start is pending).
3. Otherwise, the first assistant with the mic.

With the hotkey, a pending ChatGPT start is just one more press.

## 5. Measured comparison (ChatGPT 26.1002, 11:37–12:03Z)

| Method | Starting state | Started | Press→mic | Stops | Stop time | ChatGPT errors |
| --- | --- | --- | --- | --- | --- | --- |
| **Voice Chat hotkey** | Finder, ChatGPT hidden, ChatGPT in front, Claude in front (11 runs with the Mac in use); stops 0.3/1/3 s after mic | **35 of 35** | median 0.36 s, p90 0.43 s, max 0.67 s | **35 of 35** | ~67 ms | **0** |
| ⌃⇧V, current 1.0.14 flow, **Mac idle** | Finder, hidden, in front | 15 of 15 | median 0.51 s (with the switch), max 0.65 s | 15 of 15 | ~100 ms | 2 "interrupted" (stops 3.1 s after mic) |
| ⌃⇧V, current flow, **Mac in use** | Finder, Claude in front | **24 of 36**; only **18 of 36** within 1.5 s | median 0.5 s when fast; 6 took 1.5–8.1 s; 12 never got ChatGPT forward within 8 s | 24 of 24 | ~100 ms | 6 "interrupted" (stops at 0.4, 1.1 and 3.1 s) |
| ⌃⇧V after "wait until the window is key" | any | 0 of 13 | — | — | — | ChatGPT's Electron window never reports focus through Accessibility, so this fix can't be built |
| ChatGPT mode's own voice | — | not measured | — | — | — | No reliable way to start it (see above) |
| Any method, screen locked | — | 0 of 7 | — | — | — | Expected; already guarded |

Notes:

- "Mac in use" means the owner was using the Mac during those runs (idle time sampled at 5–34 s). The idle runs happened while the owner had stepped away; the screen locked at 11:51 from idle. I attribute the refusals to macOS declining a background app's request to bring another app forward while you're working, but I didn't prove the mechanism. Either way the hotkey path never asks for it.
- ChatGPT's session started 1.5 s (median) after it took the mic, up to 2.4 s (74 chats). Speech in that window still reaches the chat once it's live, but a ⌃⇧V stop then errors.
- No stuck lock occurred in any trial, so "a hotkey press clears it" is verified in ChatGPT's code, not yet live.

## 6. Plan

Status after the owner's go-ahead on 10-08: steps 1–4 are done on this branch (draft PR). Shipping needs the owner's go-ahead.

1. **ChatGPT through the Voice Chat hotkey** (done):
   - `ChatGPTHotkey`: read and merge `keybindings.json`, liveness check, accelerator parse.
   - Start and stop through the hotkey, with a trimmed ⌃⇧V fallback.
   - **Deleted**: `chatgptConnectingSince` and the background watcher, `Result.connecting`, `onChatGPTConnectFinished`, AppDelegate `chatgptStarts`, `endChatGPTVoiceOnceStarted`, `chatgptRestartGap`, `chatgptSettle`, the ⌘⌥O and ⌘N keystrokes, and the "connecting" menu strings.
2. **Setup and README** (done): use your hotkey or add one; a restart row in the setup window or a one-time alert; README and site copy.
3. **Claude cleanup** (done):
   - The second voice press comes after 1 s.
   - **Deleted** the unlabeled voice-button fallback, the "buttons changed" confirmation, the `MicState` width fallback, and `Mouse`. The three click fallbacks are now a second ⌘D.
4. **"Hey Codex"** (done): an alias of "Hey Chatty".
5. **Next**: release when the owner says so. After a week of logs, if the audio-aware hold never extends, replace `SpeechActivity` and `ContinuationHold` with a fixed 0.7 s hold.

## 7. Prototype on this branch

Three commits after this doc. `./build.sh` runs 166 test cases (21 new, for the keybindings file and shortcut parsing).

| | Before (1.0.14) | Prototype |
| --- | --- | --- |
| Source lines | 3,464 | 3,597. 246 deleted, 379 added: 84 for `ChatGPTHotkey.swift`, about 100 for the setup and restart flow |
| ChatGPT state | `chatgptStoppedAt`, `chatgptConnectingSince`, `chatgptLiveSince`, AppDelegate `chatgptStarts`, `Result.connecting`, `onChatGPTConnectFinished` | One `chatgptAskedAt` timestamp |
| Background work | A 15 s watcher thread per slow start | None |
| ChatGPT timing constants | Restart gap 2 s, settle 2 s, connect limit 15 s, front delay | Pending limit 10 s; the fallback keeps its front delay and a 4 s settle |
| Keystrokes to ChatGPT | ⌘⌥O (dead in 26.1002), ⌘N, ⌃⇧V, all needing ChatGPT in front | The hotkey (any app); ⌃⇧V only until ChatGPT has read the hotkey |
| Pointer moves | `Mouse.click` in 3 places | None |

So the code is not shorter, because of the new setup flow. But the fragile part, timing ChatGPT from the outside, is mostly gone.

What else changes for the user:

- With the ⌃⇧V fallback, "stop listening" during a start asks you to say it again once ChatGPT is talking, instead of queueing the stop.
- A slow start no longer reports its late connect in the menu.

### Live check of the prototype (12:34–12:39Z)

The prototype build ran in place of 1.0.14, in dry run so it ignored real wake words, driven by `heyai://open/…` and a temporary stop hook. ChatGPT was never quit.

| Check | Result |
| --- | --- |
| Launch with your hotkey already set | Logged "using yours (Control+Alt+Command+V)" |
| "Hey Chatty" ×8, "Hey Codex" ×3 (stops at 0.5 s or 2 s) | **11 of 11** started, mic in 0.34–0.70 s (including URL dispatch); 11 of 11 stopped in ~0.08 s |
| "Stop listening" 0.15 s after the request | 3 of 3 ended the chat |
| Start again 0.5 s after a stop | 3 of 3 (the old 2 s restart gap isn't needed) |
| "Hey Chatty" during a live chat | 2 of 2 left the chat running ("already in a voice chat") |
| ⌃⇧V fallback (hotkey treated as not live yet) | 3 of 3 started (0.51–0.83 s, Mac idle); 3 of 3 stopped (1.4–1.7 s, because of the 4 s settle) |
| ChatGPT's desktop log during all of the above | 0 "already starting", 0 "interrupted" |
| "Hey Claude" ×3 | 3 of 3. One needed the second press, which now came after 1.09 s; voice started 2.1 s after the request (about 3.4 s before) |
| "Hey Claude Code" ×2, then "stop listening" | 2 of 2 dictating; 2 of 2 stopped |
| Hotkey setup against a scratch keybindings file | None → added ⌃⌥⌘V and showed the alert (Later chosen, logged). Cleared, yours, yours-but-unpressable and unreadable all behaved as designed and left the file alone |
| Setup-window row | Shows "Hey AI turned on ChatGPT's voice hotkey (⌃⌥⌘V)…" with a "Restart ChatGPT now" link |
| Quit and reopen (on Apple's Chess, not ChatGPT) | Quit and reopened with a new process in about 1.3 s |

Not checked live: "Restart ChatGPT" on ChatGPT itself (never quit while the owner's Codex tasks run), and the first launch on a Mac where ChatGPT has never been opened.

To rerun the measurements, rebuild the harness described above:

- a `heyai://debug/…` URL hook and a `debugDryRun` default, both marked `// DEBUG-TEST`;
- a trial loop that records press, mic and stop times to a scratch JSON file;
- a join of that file against `~/.codex/state_5.sqlite` and ChatGPT's desktop log.

Never commit it.
