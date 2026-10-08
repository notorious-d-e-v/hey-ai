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
    private var lastAction = "" { didSet { lastActionAt = Date() } }
    private var lastActionAt = Date.distantPast
    /// The assistant whose voice chat Hey AI opened last.
    private var lastOpenedAssistant: MicActivity.Assistant?
    private var flashUntil = Date.distantPast

    private let defaults = UserDefaults.standard
    private static let showSetupNotification = Notification.Name("dev.notorious.heyai.showSetup")
    private static let statusItemName = "HeyAI"
    private var lastStartAttempt = Date.distantPast

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
        // One copy at a time: a second one (say, a fresh build) would also listen. Ask the
        // running copy to show its window, then quit this one.
        let mine = ProcessInfo.processInfo.processIdentifier
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != mine && !$0.isTerminated }) {
            Log.info("another Hey AI is already running (pid \(other.processIdentifier)); showing it and quitting this one")
            DistributedNotificationCenter.default().postNotificationName(Self.showSetupNotification, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            exit(0)
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showSetupNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.showSetup() }
        NSApp.mainMenu = Self.makeMainMenu()
        // heyai://open/<chatgpt|codex|claude|claude-code>, heyai://send/claude-code,
        // heyai://dump/<claude|chatgpt|codex>, heyai://login/<on|off>
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // New menu-bar icons join at the far left, which is the first place macOS hides
        // behind the notch when the bar is full. On first launch, start just left of
        // Control Center instead; after that, wherever the user ⌘-drags it is remembered.
        let positionKey = "NSStatusItem Preferred Position \(Self.statusItemName)"
        if defaults.object(forKey: positionKey) == nil { defaults.set(345.0, forKey: positionKey) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.statusItemName
        menu.delegate = self
        statusItem.menu = menu

        listener.allowServerRecognition = allowServerRecognition
        listener.onState = { [weak self] state in
            guard let self else { return }
            self.listenerState = state
            if case .failed(let reason) = state { self.setup.listenerProblem = reason } else { self.setup.listenerProblem = nil }
            if case .listening = state { self.setup.isListening = true } else { self.setup.isListening = false }
            self.updateIcon()
        }
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
        listener.isAssistantSpeaking = { MicActivity.assistantSpeaking() }
        listener.onNudge = { [weak self] show in
            guard let self else { return }
            if show {
                Log.info("Claude Code: asked “Done?”")
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
            self.lastAction = MenuText.forResult("Claude Code: \(reason)")
            self.launcher.stopWatchingDictation()
            self.nudge.hide()
            self.updateIcon()
        }

        if keepScreenAwake { setKeepScreenAwake(true) }

        Log.info("Hey AI started")
        updateIcon()
        // A full menu bar can take a few seconds to lay out after launch, and items move
        // as other apps come and go, so re-check whenever macOS reports a change.
        if let window = statusItem.button?.window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMoveNotification] {
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.checkMenuBarIcon()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkMenuBarIcon() }

        setup.isPaused = paused
        setup.onCanListen = { [weak self] in self?.startListeningIfPossible() }
        setup.onRestartChatGPT = { [weak self] in self?.restartChatGPT() }
        setup.onFinish = { [weak self] in self?.finishSetup() }
        // Closing the window once everything is allowed counts as done; closing it
        // earlier leaves setup to finish next time.
        setup.onClose = { [weak self] in
            guard let self else { return }
            if self.setup.allGranted {
                self.finishSetup()
            } else {
                self.setup.stopWatching()
                self.setupWindow = nil
                self.setupChanges = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
        // Listen right away if the permissions are already there; otherwise the setup
        // window asks for them, so the system prompts appear with an explanation.
        if setup.canListen && !paused { listener.start() }
        if !setupDone || !setup.allGranted { showSetup() }
        setUpChatGPTHotkey()
    }

    // MARK: ChatGPT's voice hotkey

    /// ChatGPT's Voice Chat hotkey starts and stops ChatGPT voice from any app (see
    /// ChatGPTHotkey). Use the one you set; if there's none, add ⌃⌥⌘V and, since ChatGPT
    /// only reads it when it starts, offer to restart ChatGPT.
    private func setUpChatGPTHotkey() {
        DispatchQueue.global().async {
            let result = Launcher.setUpChatGPTHotkey()
            DispatchQueue.main.async { self.chatGPTHotkeySetUp(result) }
        }
    }

    private func chatGPTHotkeySetUp(_ result: Launcher.HotkeySetup) {
        switch result {
        case .unavailable:
            return
        case .yours(let key, true):
            let added = key == UserDefaults.standard.string(forKey: "chatgptHotkeyAdded")
            Log.info("ChatGPT voice hotkey: using \(added ? "the one Hey AI added" : "yours") (\(key))")
        case .yours(let key, false):
            Log.info("ChatGPT voice hotkey: yours (\(key)) is a key Hey AI can't press, so it uses ⌃⇧V")
        case .unreadable:
            Log.info("ChatGPT voice hotkey: couldn't read ~/.codex/keybindings.json, so Hey AI left it alone and uses ⌃⇧V")
        case .failed(let error):
            Log.info("ChatGPT voice hotkey: couldn't add it: \(error)")
        case .added:
            let symbols = ChatGPTHotkey.defaultKeySymbols
            guard Launcher.running(Launcher.codexBundleID) != nil else {
                // ChatGPT reads it the next time it opens.
                Log.info("ChatGPT voice hotkey: added \(symbols)")
                lastAction = "Turned on ChatGPT's voice hotkey (\(symbols))"
                return
            }
            Log.info("ChatGPT voice hotkey: added \(symbols); it kicks in when ChatGPT restarts")
            lastAction = "ChatGPT's voice hotkey (\(symbols)) kicks in the next time ChatGPT restarts"
            if setupWindow != nil {
                setup.chatgptNeedsRestart = true
            } else {
                askToRestartChatGPT()
            }
        }
    }

    private func askToRestartChatGPT() {
        let symbols = ChatGPTHotkey.defaultKeySymbols
        let alert = NSAlert()
        alert.messageText = "Restart ChatGPT to turn on its voice hotkey?"
        alert.informativeText = "Hey AI set ChatGPT's Voice Chat hotkey to \(symbols), so it can start and stop ChatGPT voice from any app. ChatGPT picks it up when it restarts, which ends anything it's in the middle of.\n\nIf you choose Later, it kicks in the next time ChatGPT restarts."
        alert.addButton(withTitle: "Restart ChatGPT")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            restartChatGPT()
        } else {
            Log.info("ChatGPT voice hotkey: restart later")
        }
    }

    private func restartChatGPT() {
        setup.chatgptNeedsRestart = false
        launcher.restartChatGPT { [weak self] result in
            Log.info(result)
            DispatchQueue.main.async { self?.report(result) }
        }
    }

    /// Starts listening when it should be and isn't; safe to call often. After a failure
    /// (say, on-device speech not downloaded yet) it retries at most every 3 seconds.
    private func startListeningIfPossible() {
        guard !paused, setup.canListen, !listener.isRunning else { return }
        if listenerFailed && Date().timeIntervalSince(lastStartAttempt) < 3 { return }
        lastStartAttempt = Date()
        listener.start()
    }

    /// Opening Hey AI again (Finder, Spotlight, the Dock) shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return false
    }

    /// Only visible while the setup window gives Hey AI a Dock icon.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Hey AI")
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hey AI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        return main
    }

    /// macOS hides menu-bar icons behind the notch when there isn't room, without telling
    /// anyone. If that happened to ours, say so in setup. Judged by position, not by
    /// "is it on screen": the whole menu bar is off screen in full-screen apps and while
    /// recording, and that isn't our icon being crowded out. A crowded-out icon is moved
    /// to the far left (x = 0) or sits under the notch.
    private func checkMenuBarIcon() {
        guard let window = statusItem.button?.window else { return }
        let hidden = window.frame.minX <= 1 || Self.isUnderNotch(window.frame)
        guard hidden != setup.menuBarIconHidden else { return }
        setup.menuBarIconHidden = hidden
        Log.info(hidden ? "menu-bar icon is hidden (the menu bar is full)" : "menu-bar icon is visible")
    }

    private static func isUnderNotch(_ frame: NSRect) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        let notch = NSRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
        return frame.intersects(notch)
    }

    // MARK: Setup

    @objc private func showSetup() {
        // A Dock icon while setup is open, so the window can't get lost behind System Settings.
        NSApp.setActivationPolicy(.regular)
        setup.launchAtLogin = setupDone ? SMAppService.mainApp.status == .enabled : true
        if setupWindow == nil {
            setupWindow = SetupWindowController(model: setup)
            setupChanges = setup.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.setupWindow?.resizeToFit() }
            }
        }
        setup.startWatching()
        setupWindow?.present()
        checkMenuBarIcon()
    }

    private func finishSetup() {
        guard !setupDone || setupWindow != nil else { return }
        setupDone = true
        setup.stopWatching()
        setLaunchAtLogin(setup.launchAtLogin)
        let window = setupWindow
        setupWindow = nil
        setupChanges = nil
        window?.close()
        NSApp.setActivationPolicy(.accessory)
        updateIcon()
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

        switch target {
        case .chatgpt, .codex: lastOpenedAssistant = .chatgpt
        case .claude: lastOpenedAssistant = .claude
        case .claudeCode: lastOpenedAssistant = nil
        }
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
        // Prefer the voice chat Hey AI opened last: another app with the mic may be your own
        // dictation (say, into Claude) that "stop listening" shouldn't touch. A ChatGPT chat
        // that's still starting doesn't have the mic yet, but can be cancelled.
        let listening = MicActivity.assistantsListening()
        let opened = lastOpenedAssistant.flatMap { assistant in
            listening.contains(assistant) || (assistant == .chatgpt && launcher.chatgptStartPending) ? assistant : nil
        }
        guard let assistant = opened ?? MicActivity.all.first(where: listening.contains) else { return }
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
        lastAction = MenuText.forResult(result)
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
        setup.isPaused = paused
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
        lastAction = "Stopped dictating to Claude Code. Nothing was sent."
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
        guard on != (service.status == .enabled) else { return }
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

        if !setup.allGranted {
            menu.addItem(item("Finish Setting Up Hey AI…", #selector(showSetup)))
            menu.addItem(.separator())
        }
        if listener.isWatchingForSend {
            menu.addItem(item("Send Now", #selector(sendNow)))
            menu.addItem(item("Don’t Send", #selector(stopWaitingForSend)))
            menu.addItem(.separator())
        }

        // Each phrase also works as a button, for when talking isn't an option.
        menu.addItem(.sectionHeader(title: "Say"))
        for target in [WakeTarget.chatgpt, .codex, .claude, .claudeCode] {
            let row = phrase(target.wakePhrase, target.displayName, #selector(testTarget(_:)))
            row.representedObject = target.rawValue
            row.toolTip = "Opens \(target.displayName) now."
            menu.addItem(row)
        }
        let stop = phrase("stop listening", "Ends a voice chat", #selector(stopListeningNow))
        stop.toolTip = "Ends the voice chat or Claude Code dictation that's listening now."
        menu.addItem(stop)

        menu.addItem(.separator())
        menu.addItem(item(paused ? "Resume Listening" : "Pause Listening", #selector(togglePause)))

        menu.addItem(.separator())
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
        if setup.allGranted { menu.addItem(item("Set Up Hey AI…", #selector(showSetup))) }
        let troubleshooting = NSMenu()
        troubleshooting.addItem(item("Open Log", #selector(openLog)))
        troubleshooting.addItem(item("Write Claude Controls to Log", #selector(dumpClaude)))
        let troubleshootingItem = NSMenuItem(title: "Troubleshooting", action: nil, keyEquivalent: "")
        troubleshootingItem.submenu = troubleshooting
        menu.addItem(troubleshootingItem)
        menu.addItem(item("Quit Hey AI", #selector(quit), key: "q"))

        // Last, so it can match the width of everything else.
        menu.insertItem(.separator(), at: 0)
        menu.insertItem(header.menuItem(width: menu.size.width), at: 0)
    }

    private var header: MenuHeader {
        let detail: String?
        if listener.isWatchingForSend {
            detail = "Say “yes” or “send it” to send."
        } else if !lastAction.isEmpty {
            let ago = RelativeDateTimeFormatter()
            ago.unitsStyle = .full
            detail = Date().timeIntervalSince(lastActionAt) < 60
                ? lastAction : "\(lastAction), \(ago.localizedString(for: lastActionAt, relativeTo: Date()))"
        } else {
            detail = nil
        }
        if paused { return MenuHeader(status: "Paused", tone: .off, detail: detail) }
        if !setup.canListen { return MenuHeader(status: "Needs microphone and speech recognition", tone: .problem, detail: nil) }
        if listener.isWatchingForSend { return MenuHeader(status: "Dictating to Claude Code", tone: .on, detail: detail) }
        switch listenerState {
        case .stopped: return MenuHeader(status: "Starting…", tone: .off, detail: detail)
        case .listening(let onDevice):
            return MenuHeader(status: onDevice ? "Listening on-device" : "Listening, with online recognition", tone: .on, detail: detail)
        case .failed(let message): return MenuHeader(status: message, tone: .problem, detail: nil)
        }
    }

    /// A phrase you can say, highlighted per the brand, followed by what it does.
    private func phrase(_ words: String, _ does: String, _ action: Selector) -> NSMenuItem {
        let row = item(words, action)
        let font = NSFont.menuFont(ofSize: 0)
        let pill = NSTextAttachment()
        pill.image = Brand.phrasePill("“\(words)”", size: font.pointSize - 1)
        let size = pill.image!.size
        pill.bounds = CGRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
        let title = NSMutableAttributedString(attachment: pill)
        title.append(NSAttributedString(string: "  \(does)", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        row.attributedTitle = title
        return row
    }

    @objc private func stopListeningNow() {
        guard listener.isWatchingForSend || launcher.chatgptStartPending || MicActivity.assistantListening() != nil else {
            lastAction = "Nothing was listening, so there was nothing to stop"
            return
        }
        stopListening()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private var listenerFailed: Bool {
        if case .failed = listenerState { return true }
        return false
    }

    private func updateIcon() {
        let image: NSImage
        if Date() < flashUntil {
            image = Brand.menuBarImage(.heard)
        } else if paused {
            image = Brand.menuBarImage(.paused)
        } else if listenerFailed || !setup.canListen {
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
