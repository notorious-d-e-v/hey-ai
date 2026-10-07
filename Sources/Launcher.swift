import AppKit
import ApplicationServices

/// Opens an assistant straight into a new voice conversation.
///
/// - ChatGPT ("Hey Chatty") and Codex ("Hey Codex") both use the ChatGPT + Codex app
///   (ChatGPT Classic has no voice mode any more): bring it forward, open a new chat —
///   ⌘⌥O "New standalone chat" (no project folder) for ChatGPT, ⌘N "New Chat" in the
///   current folder for Codex — then ⌃⇧V, the app's own "start voice chat" shortcut.
/// - Claude ("Hey Claude"): `claude://claude.ai/new` opens a new chat, then the composer's
///   "Use voice mode" button is pressed through Accessibility. (Older claude.ai builds left
///   that button unlabeled; then it is the rightmost unlabeled button in the bottom row.)
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
        /// Claude Code dictation is running; HeyVoice should listen for a send command.
        var awaitingSend = false
        /// Screen frame (top-left origin) of the Claude Code prompt box, for the nudge.
        var anchor: CGRect?
    }

    private let queue = DispatchQueue(label: "heyvoice.launcher")
    private let monitorQueue = DispatchQueue(label: "heyvoice.dictation-monitor")
    /// The Claude Code session whose dictation HeyVoice started (launcher queue only).
    private var codeSession: (reader: AXReader, composer: CodeComposer)?
    private var dictationTimer: DispatchSourceTimer?

    /// Runs off the main thread; `completion` gets a one-line result for the menu and log.
    func open(_ target: WakeTarget, completion: @escaping (Result) -> Void) {
        queue.async {
            switch target {
            case .chatgpt: completion(Result(message: self.openVoiceChat(name: "ChatGPT", newChat: (Keys.o, [.maskCommand, .maskAlternate]))))
            case .codex: completion(Result(message: self.openVoiceChat(name: "Codex", newChat: (Keys.n, .maskCommand))))
            case .claude: completion(Result(message: self.openClaudeVoice()))
            case .claudeCode: completion(self.openClaudeCodeDictation())
            }
        }
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

    /// Opens a new chat in the ChatGPT + Codex app with `newChat`, then starts voice (⌃⇧V).
    private func openVoiceChat(name: String, newChat: (key: CGKeyCode, flags: CGEventFlags)) -> String {
        let bundleID = Self.codexBundleID
        guard Self.isInstalled(bundleID) else { return "The ChatGPT + Codex app isn't installed" }
        guard AXIsProcessTrusted() else {
            Self.activate(bundleID)
            return "\(name): opened, but HeyVoice needs Accessibility permission to start voice"
        }
        let wasRunning = Self.running(bundleID) != nil
        guard Self.activate(bundleID),
              Self.waitUntilFrontmost(bundleID, timeout: wasRunning ? 8 : 25) else {
            return "\(name) didn't come to the front"
        }
        // A cold-launched app needs a moment before its shortcuts are wired up.
        Thread.sleep(forTimeInterval: wasRunning ? 0.3 : 3)

        guard Self.isFrontmost(bundleID) else { return "\(name) lost focus before voice could start" }
        Keys.press(newChat.key, flags: newChat.flags)
        Thread.sleep(forTimeInterval: 1.0)
        guard Self.isFrontmost(bundleID) else { return "\(name) lost focus before voice could start" }
        Keys.press(Keys.v, flags: [.maskControl, .maskShift])
        return "\(name): new chat + voice shortcut sent"
    }

    // MARK: Claude

    private func openClaudeVoice() -> String {
        guard Self.isInstalled(Self.claudeBundleID) else { return "Claude isn't installed" }
        guard Self.openURL(URL(string: "claude://claude.ai/new")!) else { return "Claude didn't open a new chat" }
        guard AXIsProcessTrusted() else {
            return "Claude: opened a new chat, but HeyVoice needs Accessibility permission to start voice"
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
                if reader.waitForVoiceModeStart(near: composer, timeout: 2.5) {
                    return "Claude: voice mode started"
                }
                // A button pressed right as the page appears can be ignored; it still
                // offers "Use voice mode" when that happens, so press it once more.
                if let again = reader.findComposer(requireNewChat: false)?.voiceButtonCandidates.first,
                   again.label.lowercased().contains("voice mode") {
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
            return Result(message: "Claude Code: opened a new session, but HeyVoice needs Accessibility permission to dictate")
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
        let dictating = Result(message: "Claude Code: dictating — say “send it” or “enter” to send",
                               awaitingSend: true, anchor: composer.textArea.frame)
        codeSession = (reader, composer)
        if idle.isRecording { return dictating }

        Keys.press(Keys.d, flags: .maskCommand)
        if reader.waitForMic(composer.micButton, recording: true, baseline: idle, timeout: 2.5) {
            return dictating
        }
        Log.info("Claude Code: ⌘D didn't start dictation; clicking the mic button")
        Mouse.click(at: composer.micButton.frame.center)
        if reader.waitForMic(composer.micButton, recording: true, baseline: idle, timeout: 2.5) {
            return dictating
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

        // Stop dictation. Clicking toggles it too, if the shortcut doesn't.
        let state = reader.micState(composer.micButton)
        if state.isRecording {
            Keys.press(Keys.d, flags: .maskCommand)
            if !reader.waitForMic(composer.micButton, recording: false, baseline: state, timeout: 3) {
                Mouse.click(at: composer.micButton.frame.center)
                _ = reader.waitForMic(composer.micButton, recording: false, baseline: state, timeout: 3)
            }
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
            Keys.press(Keys.downArrow, flags: .maskCommand) // caret to the end
            for _ in 0..<trailing { Keys.press(Keys.delete, flags: []) }
            Thread.sleep(forTimeInterval: 0.3)
            let edited = reader.text(of: composer.textArea.element).trimmingCharacters(in: .whitespacesAndNewlines)
            guard edited == prompt else {
                Log.info("Claude Code: expected prompt \(prompt.count) chars after removing the send command, found \(edited.count)")
                return "Claude Code: couldn't remove the send command cleanly, so the prompt wasn't sent"
            }
        }
        Keys.press(Keys.returnKey, flags: [])
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            if reader.text(of: composer.textArea.element).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Claude Code: sent (\(prompt.count) characters)"
            }
        }
        return "Claude Code: pressed Return (couldn't confirm the prompt was sent)"
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

// MARK: - Keyboard

enum Keys {
    static let d: CGKeyCode = 2           // kVK_ANSI_D
    static let n: CGKeyCode = 45          // kVK_ANSI_N
    static let o: CGKeyCode = 31          // kVK_ANSI_O
    static let v: CGKeyCode = 9           // kVK_ANSI_V
    static let returnKey: CGKeyCode = 36  // kVK_Return
    static let delete: CGKeyCode = 51     // kVK_Delete (backspace)
    static let downArrow: CGKeyCode = 125 // kVK_DownArrow

    /// Posts a key press to the frontmost app. Needs Accessibility permission.
    static func press(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

enum Mouse {
    /// Clicks at a screen point (top-left origin, as Accessibility reports frames), then
    /// puts the pointer back.
    static func click(at point: CGPoint) {
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05)
        }
        if let original { CGWarpMouseCursorPosition(original) }
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
    /// Rightmost first.
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

/// What the dictation mic button looks like right now. While recording, its pressed state
/// flips and it widens to fit a waveform.
struct MicState: CustomStringConvertible {
    let pressed: Int?
    let width: CGFloat

    var isRecording: Bool { pressed == 1 }
    var description: String { "pressed=\(pressed.map(String.init) ?? "n/a") width=\(Int(width))" }
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

    /// The new-chat composer: the widest text area on a claude.ai page, plus the unlabeled
    /// buttons in its bottom row. Voice mode is the rightmost of those.
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

            // Current claude.ai labels the button "Use voice mode".
            let labeled = controls.filter { c in
                c.role == "AXButton" && c.label.lowercased().contains("voice mode")
            }
            if !labeled.isEmpty {
                return ClaudeComposer(textArea: textArea, webArea: webArea, voiceButtonCandidates: labeled)
            }

            // Older builds left it unlabeled: rightmost unlabeled button in the bottom row.
            let ta = textArea.frame
            let candidates = controls.filter { c in
                c.role == "AXButton" && c.label.isEmpty
                    && (16...64).contains(c.frame.width) && (16...64).contains(c.frame.height)
                    && c.frame.midY > ta.minY && c.frame.midY < ta.maxY + 90
                    && c.frame.midX > ta.minX - 40 && c.frame.midX < ta.maxX + 80
            }.sorted { $0.frame.midX > $1.frame.midX }
            guard !candidates.isEmpty else { continue }
            return ClaudeComposer(textArea: textArea, webArea: webArea, voiceButtonCandidates: candidates)
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
        return MicState(pressed: pressed, width: frame(mic.element)?.width ?? mic.frame.width)
    }

    /// Waits for dictation to start or stop. Uses the pressed state when the button reports
    /// one, otherwise its width (wider while recording).
    func waitForMic(_ mic: AXControl, recording: Bool, baseline: MicState, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let now = micState(mic)
            if let pressed = now.pressed {
                if (pressed == 1) == recording { return true }
            } else if recording ? now.width > baseline.width + 4 : now.width < baseline.width - 4 {
                return true
            }
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
            if !buttons.isEmpty && !labels.contains(where: { $0.contains("voice mode") }) {
                Log.info("Claude: composer buttons after press: \(labels)")
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return false
    }

    /// Text dump of web pages, text areas and buttons, for tuning the heuristics. When no
    /// page is visible at all, falls back to an outline of the window tree.
    func describeControls() -> [String] {
        var lines: [String] = []
        var areas = webAreas()
        if let focused = focusedWebArea() {
            lines.append("focused element is inside web area \(focused.1)")
            areas.insert(focused, at: 0)
        }
        for (webArea, url) in areas {
            lines.append("web area: \(url)")
            let controls = collect(in: webArea, roles: nil)
            let composer = controls
                .filter { ($0.role == "AXTextArea" || $0.role == "AXTextField") && $0.frame.width > 250 }
                .max { $0.frame.width < $1.frame.width }
            for c in controls {
                let f = c.frame
                // Buttons and text fields everywhere; every element around the composer.
                let nearComposer = composer.map { ta in
                    f.midY > ta.frame.minY - 20 && f.midY < ta.frame.maxY + 90
                        && f.midX > ta.frame.minX - 60 && f.midX < ta.frame.maxX + 100
                } ?? false
                guard nearComposer || ["AXButton", "AXTextArea", "AXTextField"].contains(c.role) else { continue }
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

    /// Every menu command with its keyboard shortcut, e.g. "File > New Chat ⌘N".
    func describeMenus() -> [String] {
        guard let bar = copy(app, kAXMenuBarAttribute) else { return ["no menu bar"] }
        var lines: [String] = []
        func walk(_ element: AXUIElement, path: String, depth: Int) {
            guard depth < 4 else { return }
            for child in children(element) {
                let title = string(child, kAXTitleAttribute)
                let role = string(child, kAXRoleAttribute)
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

    /// Buttons and other controls in the app's windows.
    func describeWindowControls() -> [String] {
        var lines: [String] = []
        for window in windows() {
            lines.append("window: \(string(window, kAXTitleAttribute))")
            for c in collect(in: window, roles: ["AXButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXTextArea", "AXTextField"]) {
                let f = c.frame
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
        let title = [kAXTitleAttribute, kAXDescriptionAttribute].map { string(element, $0) }.first { !$0.isEmpty } ?? ""
        lines.append(String(repeating: "  ", count: depth + 1)
                     + "\(string(element, kAXRoleAttribute)) \"\(title.prefix(40))\" children=\(kids.count)")
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
                let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
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
