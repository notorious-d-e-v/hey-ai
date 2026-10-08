import AppKit
import ApplicationServices

/// Opens an assistant straight into a new voice conversation.
///
/// - ChatGPT ("Hey Chatty") and Codex ("Hey Codex") both start the ChatGPT + Codex app's
///   voice chat (ChatGPT Classic has no voice mode any more) with its Voice Chat hotkey,
///   which works from any app (see `ChatGPTHotkey`). Until ChatGPT has read that hotkey,
///   Hey AI brings ChatGPT forward and presses ⌃⇧V, its in-app "start voice chat" shortcut.
///   "Hey Codex" is another name for the same voice chat.
/// - Claude ("Hey Claude"): `claude://claude.ai/new` opens a new chat, then the composer's
///   "Use voice mode" button is pressed through Accessibility.
/// - Claude Code ("Hey Claude Code"): `claude://code/new` opens a new session in the desktop
///   app's Code tab and ⌘D (Claude's "toggle dictation" shortcut) starts dictation. Claude
///   Code has no conversational voice mode; `finishClaudeCodeDictation` sends the prompt,
///   either on a spoken command or when `watchDictation` sees dictation stop by itself.
final class Launcher {
    static let claudeBundleID = "com.anthropic.claudefordesktop"
    /// The ChatGPT + Codex desktop app ("ChatGPT.app").
    static let codexBundleID = "com.openai.codex"

    struct Result {
        let message: String
        /// Claude Code dictation is running; Hey AI should listen for a send command.
        var awaitingSend = false
        /// Screen frame (top-left origin) of the Claude Code prompt box, for the nudge.
        var anchor: CGRect?
    }

    private let queue = DispatchQueue(label: "heyai.launcher")
    private let monitorQueue = DispatchQueue(label: "heyai.dictation-monitor")
    /// The Claude Code session whose dictation Hey AI started (launcher queue only).
    private var codeSession: (reader: AXReader, composer: CodeComposer)?
    private var dictationTimer: DispatchSourceTimer?
    /// When Hey AI last asked ChatGPT to start a voice chat (nil once it's stopped). Read from
    /// the main thread too, hence the lock.
    private var chatgptAskedAt: Date?
    private let chatgptLock = NSLock()

    /// Runs off the main thread; `completion` gets a one-line result for the menu and log.
    func open(_ target: WakeTarget, completion: @escaping (Result) -> Void) {
        queue.async {
            switch target {
            // Every voice chat starts in a new chat of its own, and it's the same voice chat
            // (ChatGPT's agent, which can hand work to Codex) whichever name you use.
            case .chatgpt: completion(Result(message: self.startVoiceChat(name: "ChatGPT")))
            case .codex: completion(Result(message: self.startVoiceChat(name: "Codex")))
            case .claude: completion(Result(message: self.openClaudeVoice()))
            case .claudeCode: completion(self.openClaudeCodeDictation())
            }
        }
    }

    /// A ChatGPT voice chat Hey AI asked for is still starting: it hasn't taken the mic yet.
    var chatgptStartPending: Bool {
        chatgptLock.lock()
        let asked = chatgptAskedAt
        chatgptLock.unlock()
        guard let asked else { return false }
        return Date().timeIntervalSince(asked) < Self.chatgptStartLimit && !MicActivity.isListening(.chatgpt)
    }

    private func setChatGPTAskedAt(_ date: Date?) {
        chatgptLock.lock()
        chatgptAskedAt = date
        chatgptLock.unlock()
    }

    /// Stops Claude Code dictation, removes the spoken command (if any), and sends the prompt.
    func finishClaudeCodeDictation(command: [String]?, completion: @escaping (String) -> Void) {
        queue.async { completion(self.sendClaudeCodePrompt(command: command)) }
    }

    /// Calls `onStop` once if Claude Code's dictation turns itself off (Claude's own
    /// timeout, or the mic button clicked). Polls the mic button twice a second.
    func watchDictation(onStop: @escaping () -> Void) {
        queue.async {
            guard let session = self.codeSession else { return }
            self.monitorQueue.async {
                self.dictationTimer?.cancel()
                let timer = DispatchSource.makeTimerSource(queue: self.monitorQueue)
                var offCount = 0
                var unreadable = 0
                timer.setEventHandler { [weak self] in
                    let state = session.reader.micState(session.composer.micButton)
                    switch state.pressed {
                    case 1?: offCount = 0; unreadable = 0
                    case 0?: offCount += 1; unreadable = 0
                    default: unreadable += 1
                    }
                    if offCount >= 2 {
                        self?.dictationTimer?.cancel()
                        self?.dictationTimer = nil
                        onStop()
                    } else if unreadable >= 6 {
                        Log.info("Claude Code: lost track of the dictation button; not auto-sending")
                        self?.dictationTimer?.cancel()
                        self?.dictationTimer = nil
                    }
                }
                timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
                timer.resume()
                self.dictationTimer = timer
            }
        }
    }

    func stopWatchingDictation() {
        monitorQueue.sync {
            dictationTimer?.cancel()
            dictationTimer = nil
        }
    }

    /// Ends the voice chat (or dictation) that `assistant` has open.
    func endVoice(_ assistant: MicActivity.Assistant, completion: @escaping (String) -> Void) {
        queue.async { completion(self.endVoiceNow(assistant)) }
    }

    /// Stops the Claude Code dictation Hey AI started, without sending.
    func stopClaudeCodeDictation(completion: @escaping (String) -> Void) {
        queue.async {
            self.codeSession = nil
            guard self.stopClaudeCodeDictationNow() else { return completion("Claude Code: couldn't stop dictation") }
            completion(self.removeStopPhraseFromPrompt() ?? "Claude Code: stopped dictating (prompt not sent)")
        }
    }

    /// Claude's dictation types "stop listening" into the prompt before Hey AI hears it and
    /// stops dictation, so delete it again. nil when there was nothing to delete or it worked.
    private func removeStopPhraseFromPrompt() -> String? {
        guard let reader = Self.claudeReader(),
              let composer = reader.findCodeComposer(requireNewSession: false) else { return nil }
        // The last words land in the prompt a moment after dictation stops.
        let text = reader.waitForStableText(composer.textArea.element, settle: 0.8, timeout: 4)
        let trailing = StopPhrase.trailingLength(text)
        guard trailing > 0 else { return nil }
        let expected = String(text.dropLast(trailing)).trimmingCharacters(in: .whitespacesAndNewlines)
        let claude = Self.claudeBundleID
        let switched = "Claude Code: stopped dictating, but you switched apps, so “stop listening” is still in the prompt"
        reader.focus(composer.textArea.element)
        guard Keys.press(Keys.downArrow, flags: .maskCommand, in: claude) else { return switched } // caret to the end
        for _ in 0..<trailing {
            guard Keys.press(Keys.delete, flags: [], in: claude) else { return switched }
        }
        Thread.sleep(forTimeInterval: 0.3)
        let edited = reader.text(of: composer.textArea.element).trimmingCharacters(in: .whitespacesAndNewlines)
        if edited != expected {
            Log.info("Claude Code: expected \(expected.count) chars after removing “stop listening”, found \(edited.count)")
        }
        return nil
    }

    func dumpClaudeControls(completion: @escaping (String) -> Void) {
        queue.async {
            guard let app = Self.running(Self.claudeBundleID) else { return completion("Claude isn't running") }
            let reader = AXReader(pid: app.processIdentifier)
            reader.enableWebAccessibility()
            Thread.sleep(forTimeInterval: 0.5)
            let lines = reader.describeControls()
            Log.info("Claude controls (\(lines.count) lines):\n" + lines.joined(separator: "\n"))
            completion("Wrote \(lines.count) Claude controls to the log")
        }
    }

    /// Writes a native app's menu commands and window controls to the log.
    func dumpAppControls(_ bundleID: String, completion: @escaping (String) -> Void) {
        queue.async {
            guard let app = Self.running(bundleID) else { return completion("\(bundleID) isn't running") }
            let reader = AXReader(pid: app.processIdentifier)
            reader.enableWebAccessibility() // Electron apps hide their page content otherwise
            Thread.sleep(forTimeInterval: 0.5)
            let lines = reader.describeMenus() + reader.describeWindowControls()
            Log.info("\(bundleID) controls (\(lines.count) lines):\n" + lines.joined(separator: "\n"))
            completion("Wrote \(lines.count) \(bundleID) controls to the log")
        }
    }

    // MARK: ChatGPT and Codex

    /// Starts a ChatGPT voice chat: with the Voice Chat hotkey when ChatGPT has it, otherwise
    /// by bringing ChatGPT forward and pressing ⌃⇧V.
    private func startVoiceChat(name: String) -> String {
        let bundleID = Self.codexBundleID
        guard Self.isInstalled(bundleID) else { return "ChatGPT isn't installed (Hey AI needs the current ChatGPT app)" }
        guard AXIsProcessTrusted() else {
            Self.activate(bundleID)
            return "\(name): opened, but Hey AI needs Accessibility permission to start voice"
        }
        // Both ways in are toggles: pressing while a chat is live stops it, and pressing while
        // one is still starting cancels it (hotkey) or collides with it (⌃⇧V).
        if MicActivity.isListening(.chatgpt) { return "\(name): already in a voice chat" }
        if chatgptStartPending { return "\(name): still starting the last voice chat" }

        if let hotkey = Self.chatgptHotkey() {
            Keys.press(hotkey.key, flags: hotkey.flags)
        } else {
            let wasRunning = Self.running(bundleID) != nil
            guard Self.activate(bundleID), Self.waitUntilFrontmost(bundleID, timeout: wasRunning ? 8 : 25) else {
                return "\(name): ChatGPT didn't come to the front, so voice wasn't started"
            }
            // A cold-launched app needs a moment before its shortcuts are wired up.
            Thread.sleep(forTimeInterval: wasRunning ? 0.05 : 3)
            guard Keys.press(Keys.v, flags: [.maskControl, .maskShift], in: bundleID) else {
                return "\(name): you switched apps, so voice wasn't started"
            }
        }
        setChatGPTAskedAt(Date())
        // Usually the chat has the microphone within half a second. Right after ChatGPT
        // updates it can take 10 s; `chatgptStartPending` keeps a second press from cancelling it.
        return Self.waitForChatGPTMic(timeout: 2)
            ? "\(name): voice chat started"
            : "\(name): asked ChatGPT for a voice chat, but it hasn't started yet"
    }

    /// The Voice Chat hotkey, once the running ChatGPT has it: it was set in ChatGPT itself, or
    /// ChatGPT started after Hey AI added it (ChatGPT reads the file only at launch).
    static func chatgptHotkey() -> (key: CGKeyCode, flags: CGEventFlags)? {
        guard let app = running(codexBundleID),
              let key = ChatGPTHotkey.key(in: try? Data(contentsOf: ChatGPTHotkey.fileURL)),
              let hotkey = ChatGPTHotkey.parse(key) else { return nil }
        let defaults = UserDefaults.standard
        if key == defaults.string(forKey: "chatgptHotkeyAdded"),
           let added = defaults.object(forKey: "chatgptHotkeyAddedAt") as? Date,
           let launched = app.launchDate, launched < added {
            return nil
        }
        return hotkey
    }

    /// What `setUpChatGPTHotkey` found or did.
    enum HotkeySetup: Equatable {
        /// ChatGPT isn't installed or set up yet; try again next launch.
        case unavailable
        /// You set one in ChatGPT. `usable` is false for a key Hey AI can't press (say, a
        /// function key or a modifier on its own), and then ⌃⇧V is used instead.
        case yours(String, usable: Bool)
        /// The keybindings file isn't one Hey AI can safely edit.
        case unreadable
        /// Hey AI added it just now. ChatGPT picks it up when it next starts.
        case added
        case failed(String)
    }

    /// Uses the Voice Chat hotkey you set in ChatGPT, or sets one if ChatGPT has none, including
    /// when it was removed in ChatGPT's settings.
    static func setUpChatGPTHotkey() -> HotkeySetup {
        let url = ChatGPTHotkey.fileURL
        // No ~/.codex yet: ChatGPT isn't installed or hasn't been opened.
        guard isInstalled(codexBundleID),
              FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return .unavailable }
        let data = try? Data(contentsOf: url)
        switch ChatGPTHotkey.binding(in: data) {
        case .set(let key): return .yours(key, usable: ChatGPTHotkey.parse(key) != nil)
        case .unreadable: return .unreadable
        case .none, .cleared: break
        }
        guard let updated = ChatGPTHotkey.adding(to: data) else { return .unreadable }
        do {
            try updated.write(to: url, options: .atomic)
        } catch {
            return .failed(error.localizedDescription)
        }
        UserDefaults.standard.set(ChatGPTHotkey.defaultKey, forKey: "chatgptHotkeyAdded")
        UserDefaults.standard.set(Date(), forKey: "chatgptHotkeyAddedAt")
        return .added
    }

    /// Quits ChatGPT and opens it again, so it reads the voice hotkey Hey AI added.
    func restartChatGPT(completion: @escaping (String) -> Void) {
        queue.async { completion(Self.restart(Self.codexBundleID, name: "ChatGPT")) }
    }

    static func restart(_ bundleID: String, name: String) -> String {
        guard let app = running(bundleID) else { return "\(name) isn't open. Its voice hotkey works once you open it." }
        let pid = app.processIdentifier
        app.terminate()
        // It may ask you to confirm first, say while it's working on something.
        let deadline = Date().addingTimeInterval(30)
        while kill(pid, 0) == 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        guard kill(pid, 0) != 0 else { return "\(name) didn't quit, so its voice hotkey kicks in the next time it restarts" }
        guard activate(bundleID) else { return "\(name) quit but didn't open again. Open it to turn on its voice hotkey." }
        return "Restarted \(name). Its voice hotkey is on."
    }

    /// How long a ChatGPT voice chat Hey AI asked for gets to take the mic before another
    /// "Hey Chatty" may ask again.
    private static let chatgptStartLimit: TimeInterval = 10
    /// ⌃⇧V stops a chat cleanly only once ChatGPT's session is up. Stops 0.4–3.1 s after the
    /// chat took the mic (about 0.4 s after the press) ended it with "Voice chat was
    /// interrupted before the session could start", and an interrupted start is the likeliest
    /// way ChatGPT gets stuck refusing new chats.
    private static let shortcutStopSettle: TimeInterval = 4

    private static func waitUntilNotListening(_ assistant: MicActivity.Assistant, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !MicActivity.isListening(assistant) { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
    }

    private static func waitForChatGPTMic(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if MicActivity.isListening(.chatgpt) { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
    }

    // MARK: Claude

    private func openClaudeVoice() -> String {
        guard Self.isInstalled(Self.claudeBundleID) else { return "Claude isn't installed" }
        guard Self.openURL(URL(string: "claude://claude.ai/new")!) else { return "Claude didn't open a new chat" }
        guard AXIsProcessTrusted() else {
            return "Claude: opened a new chat, but Hey AI needs Accessibility permission to start voice"
        }
        guard let reader = Self.claudeReader() else { return "Claude didn't start" }

        let start = Date()
        while Date().timeIntervalSince(start) < 20 {
            // Until the page reports /new, the old page (and its buttons) may still be up.
            let allowAnyClaudePage = Date().timeIntervalSince(start) > 8
            if let composer = reader.findComposer(requireNewChat: !allowAnyClaudePage),
               let button = composer.voiceButtonCandidates.first {
                Log.info("Claude: pressing voice button at \(button.frame) (\(composer.voiceButtonCandidates.count) candidates)")
                reader.press(button.element)
                // A press that works shows within 0.4 s.
                if reader.waitForVoiceModeStart(near: composer, timeout: 1) {
                    return "Claude: voice mode started"
                }
                // A button pressed right as the page appears can be ignored (about 1 in 4); it
                // still offers "Use voice mode" when that happens, so press it once more.
                if let again = reader.findComposer(requireNewChat: false)?.voiceButtonCandidates.first {
                    Log.info("Claude: voice didn't start; pressing the voice button again")
                    reader.press(again.element)
                    if reader.waitForVoiceModeStart(near: composer, timeout: 4) {
                        return "Claude: voice mode started (second press)"
                    }
                }
                return "Claude: pressed the voice button (couldn't confirm voice started)"
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        let lines = reader.describeControls()
        Log.info("Claude: voice button not found. Controls seen:\n" + lines.joined(separator: "\n"))
        return "Claude: opened a new chat but couldn't find the voice button"
    }

    // MARK: Claude Code

    private func openClaudeCodeDictation() -> Result {
        guard Self.isInstalled(Self.claudeBundleID) else { return Result(message: "Claude isn't installed") }
        guard Self.openURL(URL(string: "claude://code/new")!) else {
            return Result(message: "Claude didn't open a new Code session")
        }
        guard AXIsProcessTrusted() else {
            return Result(message: "Claude Code: opened a new session, but Hey AI needs Accessibility permission to dictate")
        }
        guard let reader = Self.claudeReader() else { return Result(message: "Claude didn't start") }

        let start = Date()
        var found: CodeComposer?
        while Date().timeIntervalSince(start) < 20 {
            // A new session lives at /epitaxy; the previous session's page is /epitaxy/<id>.
            let allowAnySession = Date().timeIntervalSince(start) > 8
            if let composer = reader.findCodeComposer(requireNewSession: !allowAnySession) {
                found = composer
                break
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard let composer = found else {
            let lines = reader.describeControls()
            Log.info("Claude Code: composer not found. Controls seen:\n" + lines.joined(separator: "\n"))
            return Result(message: "Claude Code: opened a new session but couldn't find its dictation button")
        }

        guard Self.waitUntilFrontmost(Self.claudeBundleID, timeout: 5) else {
            return Result(message: "Claude Code: Claude didn't come to the front")
        }
        reader.focus(composer.textArea.element)
        let idle = reader.micState(composer.micButton)
        Log.info("Claude Code: mic button \(idle) before dictation")
        let dictating = Result(message: "Claude Code: dictating. Say “yes” or “send it” to send.",
                               awaitingSend: true, anchor: composer.textArea.frame)
        codeSession = (reader, composer)
        if idle.isRecording { return dictating }

        let claude = Self.claudeBundleID
        let switched = Result(message: "Claude Code: you switched apps, so dictation wasn't started")
        for attempt in 1...2 {
            if attempt == 2 {
                if reader.micState(composer.micButton).isRecording { return dictating } // started late
                Log.info("Claude Code: ⌘D didn't start dictation; pressing it again")
            }
            guard Keys.press(Keys.d, flags: .maskCommand, in: claude) else { codeSession = nil; return switched }
            if reader.waitForMic(composer.micButton, recording: true, timeout: 2.5) { return dictating }
        }
        codeSession = nil
        Log.info("Claude Code: mic button \(reader.micState(composer.micButton)) after both attempts")
        return Result(message: "Claude Code: opened a new session but couldn't start dictation")
    }

    private func sendClaudeCodePrompt(command: [String]?) -> String {
        codeSession = nil
        guard let reader = Self.claudeReader() else { return "Claude isn't running" }
        Self.activate(Self.claudeBundleID)
        guard Self.waitUntilFrontmost(Self.claudeBundleID, timeout: 5) else {
            return "Claude Code: Claude didn't come to the front to send"
        }
        guard let composer = reader.findCodeComposer(requireNewSession: false) else {
            return "Claude Code: couldn't find the prompt box to send"
        }

        // Every key press below checks Claude is still in front first: if you switched
        // apps, Return must not go to Slack or a terminal.
        let claude = Self.claudeBundleID
        let switched = "Claude Code: you switched apps, so the prompt wasn't sent"

        // Stop dictation, pressing ⌘D a second time if the first one didn't take.
        for attempt in 1...2 where reader.micState(composer.micButton).isRecording {
            if attempt == 2 { Log.info("Claude Code: ⌘D didn't stop dictation; pressing it again") }
            guard Keys.press(Keys.d, flags: .maskCommand, in: claude) else { return switched }
            if reader.waitForMic(composer.micButton, recording: false, timeout: 3) { break }
        }

        // The last words land in the prompt a moment after dictation stops.
        let text = reader.waitForStableText(composer.textArea.element, settle: 1.0, timeout: 6)
        let trailing = command.map { SendPhrase.trailingLength(text, command: $0) } ?? 0
        if let command, trailing == 0 {
            Log.info("Claude Code: “\(command.joined(separator: " "))” isn't at the end of the prompt; sending it as is")
        }
        let prompt = String(text.dropLast(trailing)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return "Claude Code: nothing was dictated, so nothing was sent" }

        reader.focus(composer.textArea.element)
        if trailing > 0 {
            guard Keys.press(Keys.downArrow, flags: .maskCommand, in: claude) else { return switched } // caret to the end
            for _ in 0..<trailing {
                guard Keys.press(Keys.delete, flags: [], in: claude) else { return switched }
            }
            Thread.sleep(forTimeInterval: 0.3)
            let edited = reader.text(of: composer.textArea.element).trimmingCharacters(in: .whitespacesAndNewlines)
            guard edited == prompt else {
                Log.info("Claude Code: expected prompt \(prompt.count) chars after removing the send command, found \(edited.count)")
                return "Claude Code: couldn't remove the send command cleanly, so the prompt wasn't sent"
            }
        }
        guard Keys.press(Keys.returnKey, flags: [], in: claude) else { return switched }
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            if reader.text(of: composer.textArea.element).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Claude Code: sent (\(prompt.count) characters)"
            }
        }
        return "Claude Code: pressed Return (couldn't confirm the prompt was sent)"
    }

    // MARK: Stop listening

    private func endVoiceNow(_ assistant: MicActivity.Assistant) -> String {
        let name = assistant.rawValue
        guard AXIsProcessTrusted() else { return "\(name): Hey AI needs Accessibility permission to stop it" }
        switch assistant {
        case .claude:
            guard let app = Self.running(Self.claudeBundleID) else { return "Claude isn't running" }
            let reader = AXReader(pid: app.processIdentifier)
            reader.enableWebAccessibility()
            if let stop = reader.claudeVoiceStopButton() {
                Log.info("Claude: pressing “\(stop.label)” to end voice mode")
                reader.press(stop.element)
                // Right after voice starts, Claude sometimes ignores the first press.
                if !Self.waitUntilNotListening(.claude, timeout: 1.5), let again = reader.claudeVoiceStopButton() {
                    Log.info("Claude: still listening; pressing “\(again.label)” again")
                    reader.press(again.element)
                }
            } else if !stopClaudeCodeDictationNow() {
                let lines = reader.describeControls()
                Log.info("Claude: no Stop button found. Controls seen:\n" + lines.joined(separator: "\n"))
                return "Claude: couldn't find how to stop it"
            }
        case .chatgpt:
            // Both ways in are toggles, so with no chat live or starting a press would start one.
            let live = MicActivity.isListening(.chatgpt)
            guard live || chatgptStartPending else { return "ChatGPT: no voice chat to stop" }
            chatgptLock.lock()
            let asked = chatgptAskedAt
            chatgptLock.unlock()
            // The hotkey stops a live chat and cancels one that's still starting, from any app.
            if let hotkey = Self.chatgptHotkey() {
                Keys.press(hotkey.key, flags: hotkey.flags)
                setChatGPTAskedAt(nil)
                break
            }
            // ⌃⇧V only reaches ChatGPT in front, and can't cancel a start: pressed before the
            // chat has the mic, it would ask for a second one.
            guard live else {
                return "ChatGPT: the voice chat is still starting. Say “stop listening” again once it's talking."
            }
            if let asked {
                let wait = Self.shortcutStopSettle - Date().timeIntervalSince(asked)
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
            setChatGPTAskedAt(nil)
            Self.activate(Self.codexBundleID)
            guard Self.waitUntilFrontmost(Self.codexBundleID, timeout: 4) else {
                return "ChatGPT didn't come to the front to stop voice"
            }
            guard Keys.press(Keys.v, flags: [.maskControl, .maskShift], in: Self.codexBundleID) else {
                return "ChatGPT: you switched apps, so voice wasn't stopped"
            }
        case .chatgptClassic:
            return "ChatGPT Classic: Hey AI can't stop it"
        }
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.2)
            if !MicActivity.isListening(assistant) { return "\(name): stopped listening" }
        }
        return "\(name): asked it to stop, but it's still using the microphone"
    }

    /// Toggles Claude Code dictation off if it's on. True if it ended up off.
    private func stopClaudeCodeDictationNow() -> Bool {
        guard let app = Self.running(Self.claudeBundleID) else { return false }
        let reader = AXReader(pid: app.processIdentifier)
        reader.enableWebAccessibility()
        guard let composer = reader.findCodeComposer(requireNewSession: false) else { return false }
        guard reader.micState(composer.micButton).isRecording else { return true }
        Self.activate(Self.claudeBundleID)
        guard Self.waitUntilFrontmost(Self.claudeBundleID, timeout: 4) else { return false }
        for attempt in 1...2 {
            if attempt == 2 { Log.info("Claude Code: ⌘D didn't stop dictation; pressing it again") }
            guard Keys.press(Keys.d, flags: .maskCommand, in: Self.claudeBundleID) else { return false }
            if reader.waitForMic(composer.micButton, recording: false, timeout: 2) { return true }
        }
        return false
    }

    private static func claudeReader() -> AXReader? {
        guard let app = waitUntilRunning(claudeBundleID, timeout: 25) else { return nil }
        activate(claudeBundleID)
        let reader = AXReader(pid: app.processIdentifier)
        reader.enableWebAccessibility()
        return reader
    }

    // MARK: App helpers

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func running(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    static func isFrontmost(_ bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Launches the app if needed and asks for it to come to the front.
    @discardableResult
    static func activate(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let done = DispatchSemaphore(value: 0)
        var ok = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            ok = app != nil && error == nil
            if let error { Log.info("couldn't open \(bundleID): \(error.localizedDescription)") }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 20)
        return ok
    }

    static func openURL(_ url: URL) -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let done = DispatchSemaphore(value: 0)
        var ok = false
        NSWorkspace.shared.open(url, configuration: config) { app, error in
            ok = app != nil && error == nil
            if let error { Log.info("couldn't open \(url.absoluteString): \(error.localizedDescription)") }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 20)
        return ok
    }

    static func waitUntilRunning(_ bundleID: String, timeout: TimeInterval) -> NSRunningApplication? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let app = running(bundleID), app.isFinishedLaunching { return app }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return nil
    }

    /// Frontmost with a focused window — or frontmost for 1.5 s, since some apps (ChatGPT
    /// with a voice overlay up) don't report a focused window at all.
    static func waitUntilFrontmost(_ bundleID: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var frontSince: Date?
        repeat {
            if isFrontmost(bundleID), let app = running(bundleID) {
                frontSince = frontSince ?? Date()
                if AXReader(pid: app.processIdentifier).focusedWindow() != nil
                    || Date().timeIntervalSince(frontSince!) > 1.5 {
                    return true
                }
            } else {
                frontSince = nil
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        Log.info("waiting for \(bundleID): frontmost app is \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")")
        return false
    }
}

// MARK: - Session

enum Session {
    /// True while the lock screen is up. Simulated key presses and clicks go to the lock
    /// screen then, not to the app.
    static var isScreenLocked: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return info["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

// MARK: - Keyboard

enum Keys {
    static let d: CGKeyCode = 2           // kVK_ANSI_D
    static let v: CGKeyCode = 9           // kVK_ANSI_V
    static let returnKey: CGKeyCode = 36  // kVK_Return
    static let delete: CGKeyCode = 51     // kVK_Delete (backspace)
    static let downArrow: CGKeyCode = 125 // kVK_DownArrow

    /// Presses a key only if `bundleID` is still the frontmost app, so a key meant for
    /// Claude or ChatGPT can never land in whatever you switched to. False if it wasn't.
    @discardableResult
    static func press(_ key: CGKeyCode, flags: CGEventFlags, in bundleID: String) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            Log.info("didn't press key \(key): \(bundleID) is no longer in front")
            return false
        }
        press(key, flags: flags)
        return true
    }

    /// Posts a key press to the frontmost app. Needs Accessibility permission.
    static func press(_ key: CGKeyCode, flags: CGEventFlags) {
        if Session.isScreenLocked { Log.info("screen is locked: key \(key) goes to the lock screen, not the app") }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - Accessibility

struct AXControl {
    let element: AXUIElement
    let role: String
    let subrole: String
    let label: String
    let frame: CGRect
}

struct ClaudeComposer {
    let textArea: AXControl
    let webArea: AXUIElement
    /// The "Use voice mode" buttons on the page (there is one).
    let voiceButtonCandidates: [AXControl]

    /// The composer box plus its bottom row of buttons.
    var region: CGRect {
        let f = textArea.frame
        return CGRect(x: f.minX - 40, y: f.minY, width: f.width + 120, height: f.height + 90)
    }
}

struct CodeComposer {
    let textArea: AXControl
    let micButton: AXControl
}

/// The dictation mic button's pressed state (1 while recording), or nil if it can't be read.
struct MicState: CustomStringConvertible {
    let pressed: Int?

    var isRecording: Bool { pressed == 1 }
    var description: String { "pressed=\(pressed.map(String.init) ?? "n/a")" }
}

final class AXReader {
    let app: AXUIElement

    init(pid: pid_t) {
        app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.5)
    }

    /// Electron apps only build their web accessibility tree when asked.
    @discardableResult
    func enableWebAccessibility() -> AXError {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    func focusedWindow() -> AXUIElement? {
        guard let value = copy(app, kAXFocusedWindowAttribute) else { return nil }
        return (value as! AXUIElement)
    }

    func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// The new-chat composer: the widest text area on a claude.ai page, plus its "Use voice
    /// mode" button.
    func findComposer(requireNewChat: Bool) -> ClaudeComposer? {
        var areas = webAreas()
        if let focused = focusedWebArea() { areas.insert(focused, at: 0) }
        for (webArea, url) in areas {
            guard let components = URLComponents(string: url),
                  components.host?.hasSuffix("claude.ai") == true else { continue }
            if requireNewChat && components.path != "/new" { continue }

            let controls = collect(in: webArea, roles: ["AXTextArea", "AXTextField", "AXButton"])
            guard let textArea = controls
                .filter({ ($0.role == "AXTextArea" || $0.role == "AXTextField") && $0.frame.width > 250 })
                .max(by: { $0.frame.width < $1.frame.width }) else { continue }

            let labeled = controls.filter { c in
                c.role == "AXButton" && c.label.lowercased().contains("voice mode")
            }
            guard !labeled.isEmpty else { continue }
            return ClaudeComposer(textArea: textArea, webArea: webArea, voiceButtonCandidates: labeled)
        }
        return nil
    }

    /// The Claude Code prompt box and its dictation mic button ("Press and hold to record").
    func findCodeComposer(requireNewSession: Bool) -> CodeComposer? {
        var areas = webAreas()
        if let focused = focusedWebArea() { areas.insert(focused, at: 0) }
        for (webArea, url) in areas {
            guard let components = URLComponents(string: url),
                  components.host?.hasSuffix("claude.ai") == true,
                  components.path.hasPrefix("/epitaxy") else { continue }
            if requireNewSession && components.path != "/epitaxy" { continue }

            let controls = collect(in: webArea, roles: ["AXTextArea", "AXCheckBox", "AXButton"])
            guard let textArea = controls
                .filter({ $0.role == "AXTextArea" && $0.frame.width > 250 })
                .max(by: { $0.frame.width < $1.frame.width }) else { continue }
            let ta = textArea.frame
            let mic = controls.filter { c in
                let label = c.label.lowercased()
                return (label.contains("record") || label.contains("dictat") || label.contains("microphone"))
                    && !label.contains("settings")
                    && c.frame.midY > ta.minY - 10 && c.frame.midY < ta.maxY + 80
            }.min { abs($0.frame.midX - ta.minX) < abs($1.frame.midX - ta.minX) }
            guard let mic else { continue }
            return CodeComposer(textArea: textArea, micButton: mic)
        }
        return nil
    }

    func micState(_ mic: AXControl) -> MicState {
        let pressed = (copy(mic.element, kAXValueAttribute) as? NSNumber)?.intValue
        return MicState(pressed: pressed)
    }

    /// Waits for dictation to start or stop.
    func waitForMic(_ mic: AXControl, recording: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let pressed = micState(mic).pressed, (pressed == 1) == recording { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    func text(of element: AXUIElement) -> String {
        string(element, kAXValueAttribute)
    }

    /// The text once it has stopped changing for `settle` seconds.
    func waitForStableText(_ element: AXUIElement, settle: TimeInterval, timeout: TimeInterval) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = text(of: element)
        var lastChange = Date()
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            let now = text(of: element)
            if now != last {
                last = now
                lastChange = Date()
            } else if Date().timeIntervalSince(lastChange) >= settle {
                break
            }
        }
        return last
    }

    func focus(_ element: AXUIElement) {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// The Stop / Cancel button of a live (or connecting) Claude voice chat.
    func claudeVoiceStopButton() -> AXControl? {
        var areas = webAreas()
        if let focused = focusedWebArea() { areas.insert(focused, at: 0) }
        for (webArea, url) in areas {
            guard let components = URLComponents(string: url),
                  components.host?.hasSuffix("claude.ai") == true,
                  !components.path.hasPrefix("/epitaxy") else { continue }
            let controls = collect(in: webArea, roles: ["AXTextArea", "AXButton"])
            guard let textArea = controls
                .filter({ $0.role == "AXTextArea" && $0.frame.width > 250 })
                .max(by: { $0.frame.width < $1.frame.width }) else { continue }
            let region = ClaudeComposer(textArea: textArea, webArea: webArea, voiceButtonCandidates: []).region
            if let stop = controls.first(where: { c in
                let label = c.label.lowercased()
                return c.role == "AXButton" && region.contains(c.frame.center)
                    && (label == "stop" || label == "cancel" || label.contains("end voice"))
            }) {
                return stop
            }
        }
        return nil
    }

    /// Once pressed, the button stops offering "Use voice mode" (it becomes Cancel / Stop
    /// while connecting and live).
    func waitForVoiceModeStart(near composer: ClaudeComposer, timeout: TimeInterval) -> Bool {
        let region = composer.region
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let buttons = collect(in: composer.webArea, roles: ["AXButton"])
                .filter { region.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            let labels = buttons.map { $0.label.lowercased() }
            if labels.contains(where: { $0 == "cancel" || $0 == "stop" || $0.contains("end voice") }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return false
    }

    /// A page URL with conversation and session IDs blanked, safe to paste in an issue.
    static func redacted(_ url: String) -> String {
        guard var parts = URLComponents(string: url) else { return "<url>" }
        parts.query = nil
        parts.fragment = nil
        parts.path = parts.path.split(separator: "/").map { segment in
            segment.count > 12 || segment.contains(where: \.isNumber) ? "<id>" : String(segment)
        }.reduce("") { "\($0)/\($1)" }
        return parts.string ?? "<url>"
    }

    /// Dump of the controls around the prompt box, for fixing the button lookups when an
    /// app changes its layout. It lists only roles, names and positions near the composer:
    /// never text you typed or dictated, and never the sidebar (whose buttons are named
    /// after your chats). When no page is visible, it outlines the window tree instead.
    func describeControls() -> [String] {
        var lines: [String] = []
        var areas = webAreas()
        if let focused = focusedWebArea() {
            lines.append("focused element is inside web area \(Self.redacted(focused.1))")
            areas.insert(focused, at: 0)
        }
        for (webArea, url) in areas {
            lines.append("web area: \(Self.redacted(url))")
            let controls = collect(in: webArea, roles: nil)
            guard let composer = controls
                .filter({ ($0.role == "AXTextArea" || $0.role == "AXTextField") && $0.frame.width > 250 })
                .max(by: { $0.frame.width < $1.frame.width }) else {
                lines.append("  no prompt box on this page")
                continue
            }
            let ta = composer.frame
            for c in controls where c.role != "AXStaticText" {
                let f = c.frame
                guard f.midY > ta.minY - 20, f.midY < ta.maxY + 90,
                      f.midX > ta.minX - 60, f.midX < ta.maxX + 100 else { continue }
                lines.append("  \(c.role)\(c.subrole.isEmpty ? "" : "/\(c.subrole)") \"\(c.label)\" x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height))")
            }
        }
        if areas.isEmpty {
            let wins = windows()
            lines.append("no web areas; \(wins.count) window(s)")
            for window in wins { outline(window, depth: 0, into: &lines) }
        }
        return lines
    }

    /// Every menu command with its keyboard shortcut, e.g. "File > New Chat ⌘N". Skips the
    /// menus that list your chats or windows by name.
    func describeMenus() -> [String] {
        guard let bar = copy(app, kAXMenuBarAttribute) else { return ["no menu bar"] }
        var lines: [String] = []
        func walk(_ element: AXUIElement, path: String, depth: Int) {
            guard depth < 4 else { return }
            for child in children(element) {
                let title = string(child, kAXTitleAttribute)
                let role = string(child, kAXRoleAttribute)
                if depth == 0, ["Chats", "History", "Window"].contains(title) { continue }
                let here = title.isEmpty ? path : (path.isEmpty ? title : "\(path) > \(title)")
                if role == "AXMenuItem", !title.isEmpty {
                    let key = string(child, kAXMenuItemCmdCharAttribute)
                    let mods = (copy(child, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
                    lines.append("  menu: \(here)\(key.isEmpty ? "" : "  [\(modifierString(mods))\(key)]")")
                }
                walk(child, path: here, depth: depth + 1)
            }
        }
        walk(bar as! AXUIElement, path: "", depth: 0)
        return lines
    }

    /// Controls around each window's prompt box (the sidebar is skipped: its buttons are
    /// named after your chats).
    func describeWindowControls() -> [String] {
        var lines: [String] = []
        for window in windows() {
            lines.append("window")
            let controls = collect(in: window, roles: ["AXButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXTextArea", "AXTextField"])
            let composer = controls
                .filter { ($0.role == "AXTextArea" || $0.role == "AXTextField") && $0.frame.width > 250 }
                .max { $0.frame.width < $1.frame.width }
            guard let ta = composer?.frame else {
                // Without a prompt box, names could be chat titles: count roles only.
                let roles = Dictionary(grouping: controls, by: \.role).map { "\($0.key)×\($0.value.count)" }.sorted()
                lines.append("  no prompt box; controls: \(roles.joined(separator: ", "))")
                continue
            }
            for c in controls {
                let f = c.frame
                guard f.midY > ta.minY - 40, f.midY < ta.maxY + 90,
                      f.midX > ta.minX - 60, f.midX < ta.maxX + 100 else { continue }
                let extra = [("id", "AXIdentifier"), ("help", kAXHelpAttribute), ("desc", kAXDescriptionAttribute)]
                    .compactMap { name, attribute -> String? in
                        let value = string(c.element, attribute)
                        return value.isEmpty || value == c.label ? nil : "\(name)=\"\(value)\""
                    }.joined(separator: " ")
                lines.append("  \(c.role)\(c.subrole.isEmpty ? "" : "/\(c.subrole)") \"\(c.label)\" \(extra) x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height))")
            }
        }
        return lines
    }

    /// kAXMenuItemCmdModifiers: ⌘ is implied unless bit 3 is set; 1 = ⇧, 2 = ⌥, 4 = ⌃.
    private func modifierString(_ mods: Int) -> String {
        var s = ""
        if mods & 4 != 0 { s += "⌃" }
        if mods & 2 != 0 { s += "⌥" }
        if mods & 1 != 0 { s += "⇧" }
        if mods & 8 == 0 { s += "⌘" }
        return s
    }

    private func outline(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth <= 8, lines.count < 150 else { return }
        let kids = children(element)
        // Roles only: titles here can be window or chat names.
        lines.append(String(repeating: "  ", count: depth + 1)
                     + "\(string(element, kAXRoleAttribute)) children=\(kids.count)")
        for kid in kids { outline(kid, depth: depth + 1, into: &lines) }
    }

    // MARK: Tree walking

    /// The page holding keyboard focus — on a fresh /new page that is the composer.
    private func focusedWebArea() -> (AXUIElement, String)? {
        guard let focused = copy(app, kAXFocusedUIElementAttribute) else { return nil }
        var element = focused as! AXUIElement
        for _ in 0..<80 {
            if string(element, kAXRoleAttribute) == "AXWebArea" { return (element, url(element) ?? "") }
            guard let parent = copy(element, kAXParentAttribute) else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }

    private func webAreas() -> [(AXUIElement, String)] {
        var found: [(AXUIElement, String)] = []
        var queue: [AXUIElement] = windows()
        var visited = 0
        while !queue.isEmpty, visited < 4000 {
            let element = queue.removeFirst()
            visited += 1
            if string(element, kAXRoleAttribute) == "AXWebArea" {
                found.append((element, url(element) ?? ""))
                continue
            }
            queue.append(contentsOf: children(element))
        }
        return found
    }

    /// Breadth-first walk; `roles: nil` collects every element that has a frame.
    private func collect(in root: AXUIElement, roles: Set<String>?, limit: Int = 8000) -> [AXControl] {
        var result: [AXControl] = []
        var queue: [AXUIElement] = [root]
        var index = 0
        while index < queue.count, index < limit {
            let element = queue[index]
            index += 1
            let role = string(element, kAXRoleAttribute)
            if roles?.contains(role) ?? true, let frame = frame(element) {
                // Never a control's value: for text boxes that is what you typed or dictated.
                let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                    .map { string(element, $0) }
                    .first { !$0.isEmpty } ?? ""
                result.append(AXControl(element: element, role: role,
                                        subrole: string(element, kAXSubroleAttribute),
                                        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                                        frame: frame))
            }
            queue.append(contentsOf: children(element))
        }
        if index >= limit { Log.info("AX walk stopped at \(limit) elements") }
        return result
    }

    /// The app's windows. Falls back to the main/focused window and the app's children,
    /// since some apps answer kAXWindows slowly or not at all.
    private func windows() -> [AXUIElement] {
        if let list = copy(app, kAXWindowsAttribute) as? [AXUIElement], !list.isEmpty { return list }
        var found: [AXUIElement] = []
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let value = copy(app, attribute) { found.append(value as! AXUIElement) }
        }
        found += children(app).filter { string($0, kAXRoleAttribute) == "AXWindow" }
        var error = AXError.success
        var value: CFTypeRef?
        error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        Log.info("kAXWindows returned \(error.rawValue); fallback found \(found.count) window(s)")
        return found
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        (copy(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        (copy(element, attribute) as? String) ?? ""
    }

    private func url(_ element: AXUIElement) -> String? {
        let value = copy(element, "AXURL")
        if let url = value as? URL { return url.absoluteString }
        return value as? String
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = copy(element, kAXPositionAttribute),
              let sizeValue = copy(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
