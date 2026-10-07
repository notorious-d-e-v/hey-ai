import AppKit
import ApplicationServices
import AVFoundation
import Combine
import IOKit.pwr_mgt
import ServiceManagement
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let listener = WakeListener()
    private let launcher = Launcher()
    private let nudge = NudgePanel()
    /// Where the Claude Code prompt box is, so the nudge can sit just above it.
    private var nudgeAnchor: CGRect?

    private let setup = SetupModel()
    private var setupWindow: SetupWindowController?
    private var setupChanges: AnyCancellable?

    private var listenerState: WakeListener.State = .stopped
    private var lastHeard = ""
    private var lastAction = ""
    private var flashUntil = Date.distantPast

    private let defaults = UserDefaults.standard

    /// Held while "Keep Screen Awake" is on.
    private var displayAssertion: IOPMAssertionID = 0

    private var keepScreenAwake: Bool {
        get { defaults.bool(forKey: "keepScreenAwake") }
        set { defaults.set(newValue, forKey: "keepScreenAwake") }
    }

    private var setupDone: Bool {
        get { defaults.bool(forKey: "setupDone") }
        set { defaults.set(newValue, forKey: "setupDone") }
    }

    private var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }

    private var allowServerRecognition: Bool {
        get { defaults.bool(forKey: "allowServerRecognition") }
        set { defaults.set(newValue, forKey: "allowServerRecognition") }
    }

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // heyai://open/<chatgpt|codex|claude|claude-code>, heyai://send/claude-code,
        // heyai://dump/<claude|chatgpt|codex>, heyai://login/<on|off>
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu

        listener.allowServerRecognition = allowServerRecognition
        listener.onState = { [weak self] state in
            self?.listenerState = state
            self?.updateIcon()
        }
        listener.onHeard = { [weak self] text in self?.lastHeard = text }
        listener.onWake = { [weak self] match, heard in
            // Saying a wake phrase while talking to an assistant shouldn't open a new one.
            if let busy = MicActivity.assistantListening() {
                Log.info("heard \"\(match.phrase)\" but \(busy.rawValue) is already listening; ignored")
                self?.lastAction = "Ignored “\(match.target.wakePhrase)”: \(busy.rawValue) is already listening"
                return
            }
            // Apps can't be driven behind the lock screen (macOS hides their content and
            // sends input to the lock screen), so don't try.
            if Session.isScreenLocked {
                Log.info("heard \"\(match.phrase)\" while the screen is locked; ignored")
                self?.lastAction = "Ignored “\(match.target.wakePhrase)”: the screen was locked"
                return
            }
            Log.info("heard \"\(match.phrase)\" → \(match.target.displayName)")
            self?.setupHeard(match.target)
            self?.trigger(match.target)
        }
        listener.onSendPhrase = { [weak self] command in
            Log.info("heard “\(command.joined(separator: " "))” → send")
            self?.sendClaudeCodePrompt(command: command)
        }
        listener.onStopPhrase = { [weak self] in self?.stopListening() }
        listener.onNudge = { [weak self] show in
            guard let self else { return }
            if show {
                self.nudge.show(above: self.nudgeAnchor)
                let tick = NSSound(named: "Tink")
                tick?.volume = 0.3
                tick?.play()
            } else {
                self.nudge.hide()
            }
        }
        listener.onSendWatchEnded = { [weak self] reason in
            guard let self else { return }
            Log.info("Claude Code: \(reason)")
            self.lastAction = "Claude Code: \(reason)"
            self.launcher.stopWatchingDictation()
            self.nudge.hide()
            self.updateIcon()
        }

        if keepScreenAwake { setKeepScreenAwake(true) }

        Log.info("Hey AI started")
        updateIcon()

        setup.onCanListen = { [weak self] in
            guard let self, !self.paused else { return }
            self.listener.start()
        }
        setup.onFinish = { [weak self] in self?.finishSetup() }
        // Listen right away if the permissions are already there; otherwise the setup
        // window asks for them, so the system prompts appear with an explanation.
        if setup.canListen && !paused { listener.start() }
        if !setupDone || !setup.allGranted { showSetup() }
    }

    // MARK: Setup

    @objc private func showSetup() {
        if setupWindow == nil {
            setupWindow = SetupWindowController(model: setup)
            setupChanges = setup.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.setupWindow?.resizeToFit() }
            }
        }
        setup.startWatching()
        setupWindow?.present()
    }

    private func finishSetup() {
        setupDone = true
        setup.stopWatching()
        setLaunchAtLogin(setup.launchAtLogin)
        setupWindow?.close()
        setupWindow = nil
        setupChanges = nil
    }

    /// The first wake phrase during setup: show it, then get out of the way.
    private func setupHeard(_ target: WakeTarget) {
        guard let window = setupWindow?.window, window.isVisible, setup.allGranted else { return }
        setup.lastHeard = "Heard “\(target.wakePhrase)”. Opening \(target.displayName)…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.finishSetup() }
    }

    private func requestPermissionsAndStart() {
        AVCaptureDevice.requestAccess(for: .audio) { micGranted in
            SFSpeechRecognizer.requestAuthorization { speechStatus in
                DispatchQueue.main.async {
                    if !micGranted {
                        self.listenerState = .failed("Microphone access is off. Allow Hey AI in System Settings → Privacy & Security → Microphone.")
                    } else if speechStatus != .authorized {
                        self.listenerState = .failed("Speech recognition is off. Allow Hey AI in System Settings → Privacy & Security → Speech Recognition.")
                    } else if !self.paused {
                        self.listener.start()
                    }
                    self.updateIcon()
                }
            }
        }
    }

    // MARK: Actions

    private func trigger(_ target: WakeTarget) {
        NSSound(named: "Pop")?.play()
        flashUntil = Date().addingTimeInterval(2)
        updateIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { [weak self] in self?.updateIcon() }

        launcher.open(target) { [weak self] result in
            Log.info(result.message)
            DispatchQueue.main.async {
                guard let self else { return }
                self.report(result.message)
                if result.awaitingSend {
                    self.nudgeAnchor = result.anchor
                    self.listener.watchForSend()
                    self.launcher.watchDictation { [weak self] in
                        DispatchQueue.main.async {
                            guard let self, self.listener.isWatchingForSend else { return }
                            Log.info("Claude Code: dictation stopped on its own → send")
                            self.listener.stopWatchingForSend()
                            self.sendClaudeCodePrompt(command: nil)
                        }
                    }
                    self.updateIcon()
                }
            }
        }
    }

    @objc private func toggleKeepScreenAwake() {
        keepScreenAwake.toggle()
        setKeepScreenAwake(keepScreenAwake)
    }

    /// Stops the display from sleeping on idle (like `caffeinate -d`), so the Mac doesn't
    /// auto-lock and wake phrases keep working.
    private func setKeepScreenAwake(_ on: Bool) {
        if on, displayAssertion == 0 {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Keep listening for wake phrases" as CFString, &displayAssertion)
            Log.info("keep screen awake on (\(result == kIOReturnSuccess ? "ok" : "error \(result)"))")
        } else if !on, displayAssertion != 0 {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
            Log.info("keep screen awake off")
        }
    }

    /// "Stop listening": end whatever voice chat or dictation is open, right away.
    private func stopListening() {
        if listener.isWatchingForSend {
            Log.info("heard “stop listening” → stop Claude Code dictation")
            listener.stopWatchingForSend()
            launcher.stopWatchingDictation()
            nudge.hide()
            updateIcon()
            launcher.stopClaudeCodeDictation { [weak self] result in
                Log.info(result)
                DispatchQueue.main.async { self?.report(result) }
            }
            return
        }
        guard let assistant = MicActivity.assistantListening() else { return }
        Log.info("heard “stop listening” → stop \(assistant.rawValue)\(Session.isScreenLocked ? " (screen locked)" : "")")
        launcher.endVoice(assistant) { [weak self] result in
            Log.info(result)
            DispatchQueue.main.async { self?.report(result) }
        }
    }

    /// `command` is the spoken send command to remove from the prompt; nil when dictation
    /// stopped on its own or Send Now was chosen.
    private func sendClaudeCodePrompt(command: [String]?) {
        launcher.stopWatchingDictation()
        nudge.hide()
        updateIcon()
        NSSound(named: "Pop")?.play()
        launcher.finishClaudeCodeDictation(command: command) { [weak self] result in
            Log.info(result)
            DispatchQueue.main.async { self?.report(result) }
        }
    }

    private func report(_ result: String) {
        lastAction = result
        if result.contains("couldn't") || result.contains("didn't") || result.contains("needs")
            || result.contains("wasn't") {
            NSSound(named: "Basso")?.play()
        }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        let name = url.lastPathComponent.lowercased()
        switch (url.host?.lowercased(), name) {
        case ("open", _) where WakeTarget(rawValue: name) != nil:
            trigger(WakeTarget(rawValue: name)!)
        case ("login", "on"), ("login", "off"):
            setLaunchAtLogin(name == "on")
        case ("send", "claude-code"):
            sendNow()
        case ("dump", "chatgpt"), ("dump", "codex"):
            launcher.dumpAppControls(Launcher.codexBundleID) { result in
                Log.info(result)
                DispatchQueue.main.async { self.lastAction = result }
            }
        case ("dump", "claude"):
            launcher.dumpClaudeControls { result in
                Log.info(result)
                DispatchQueue.main.async { self.lastAction = result }
            }
        default:
            Log.info("ignored URL \(string)")
        }
    }

    @objc private func togglePause() {
        paused.toggle()
        if paused {
            listener.stop()
        } else {
            requestPermissionsAndStart()
        }
        updateIcon()
    }

    @objc private func testTarget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let target = WakeTarget(rawValue: raw) else { return }
        trigger(target)
    }

    @objc private func sendNow() {
        listener.stopWatchingForSend()
        sendClaudeCodePrompt(command: nil)
    }

    @objc private func stopWaitingForSend() {
        listener.stopWatchingForSend()
        launcher.stopWatchingDictation()
        nudge.hide()
        lastAction = "Claude Code: stopped waiting to send"
        updateIcon()
    }

    @objc private func dumpClaude() {
        launcher.dumpClaudeControls { result in
            DispatchQueue.main.async { self.lastAction = result }
        }
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    @objc private func toggleServerRecognition() {
        allowServerRecognition.toggle()
        listener.allowServerRecognition = allowServerRecognition
        listener.stop()
        if !paused { requestPermissionsAndStart() }
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(SMAppService.mainApp.status != .enabled)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
            Log.info("launch at login \(on ? "on" : "off") (status \(service.status.rawValue))")
        } catch {
            Log.info("launch at login: \(error.localizedDescription)")
            lastAction = "Launch at login failed: \(error.localizedDescription)"
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(info(statusLine))
        if listener.isWatchingForSend {
            menu.addItem(info("Dictating to Claude Code — say “send it” or “enter”"))
            menu.addItem(item("Send Now", #selector(sendNow)))
            menu.addItem(item("Don’t Send", #selector(stopWaitingForSend)))
        }
        menu.addItem(info("“Hey Chatty” → ChatGPT voice"))
        menu.addItem(info("“Hey Codex” → Codex voice"))
        menu.addItem(info("“Hey Claude” → Claude voice"))
        menu.addItem(info("“Hey Claude Code” → Claude Code dictation"))
        if !lastHeard.isEmpty, case .listening = listenerState {
            menu.addItem(info("Heard: …\(String(lastHeard.suffix(48)))"))
        }
        if !lastAction.isEmpty { menu.addItem(info("Last: \(lastAction)")) }

        menu.addItem(.separator())
        menu.addItem(item(paused ? "Resume Listening" : "Pause Listening", #selector(togglePause)))

        let testMenu = NSMenu()
        for target in WakeTarget.allCases {
            let entry = item("Open \(target.displayName) Now", #selector(testTarget(_:)))
            entry.representedObject = target.rawValue
            testMenu.addItem(entry)
        }
        testMenu.addItem(.separator())
        testMenu.addItem(item("Write Claude Controls to Log", #selector(dumpClaude)))
        testMenu.addItem(item("Open Log", #selector(openLog)))
        let testItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        testItem.submenu = testMenu
        menu.addItem(testItem)

        menu.addItem(.separator())
        menu.addItem(item(setup.allGranted ? "Set Up Hey AI…" : "Finish Setting Up Hey AI…", #selector(showSetup)))
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let awake = item("Keep Screen Awake", #selector(toggleKeepScreenAwake))
        awake.state = keepScreenAwake ? .on : .off
        awake.toolTip = "The display won't sleep on its own, so the Mac doesn't auto-lock and wake phrases keep working. An unattended Mac stays unlocked."
        menu.addItem(awake)
        let server = item("Allow Online Speech Recognition", #selector(toggleServerRecognition))
        server.state = allowServerRecognition ? .on : .off
        server.toolTip = "Only used if on-device recognition is unavailable. Sends microphone audio to Apple."
        menu.addItem(server)

        menu.addItem(.separator())
        menu.addItem(item("Quit Hey AI", #selector(quit), key: "q"))
    }

    private var statusLine: String {
        if paused { return "Paused" }
        switch listenerState {
        case .stopped: return "Starting…"
        case .listening(let onDevice): return onDevice ? "Listening (on-device)" : "Listening (online)"
        case .failed(let message): return message
        }
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateIcon() {
        let image: NSImage
        if Date() < flashUntil {
            image = Brand.menuBarImage(.heard)
        } else if paused {
            image = Brand.menuBarImage(.paused)
        } else if case .failed = listenerState {
            image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Hey AI needs attention")!
            image.isTemplate = true
        } else if listener.isWatchingForSend {
            image = Brand.menuBarImage(.dictating)
        } else {
            image = Brand.menuBarImage(.listening)
        }
        statusItem?.button?.image = image
    }
}
