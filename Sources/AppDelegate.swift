import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let listener = WakeListener()
    private let launcher = Launcher()

    private var listenerState: WakeListener.State = .stopped
    private var lastHeard = ""
    private var lastAction = ""
    private var flashUntil = Date.distantPast

    private let defaults = UserDefaults.standard

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
        // heyvoice://open/<chatgpt|codex|claude|claude-code>, heyvoice://send/claude-code,
        // heyvoice://dump/claude
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu

        listener.allowServerRecognition = allowServerRecognition
        listener.onState = { [weak self] state in
            self?.listenerState = state
            self?.updateIcon()
        }
        listener.onHeard = { [weak self] text in self?.lastHeard = text }
        listener.onWake = { [weak self] match, heard in
            Log.info("heard \"\(match.phrase)\" → \(match.target.displayName)")
            self?.trigger(match.target)
        }
        listener.onSendPhrase = { [weak self] in
            Log.info("heard “send it”")
            self?.sendClaudeCodePrompt()
            self?.updateIcon()
        }
        listener.onSendWatchEnded = { [weak self] reason in
            Log.info("Claude Code: \(reason)")
            self?.lastAction = "Claude Code: \(reason)"
            self?.updateIcon()
        }

        Log.info("HeyVoice started")
        updateIcon()
        if !AXIsProcessTrusted() {
            // Accessibility lets HeyVoice press ChatGPT's voice shortcut and Claude's voice button.
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        requestPermissionsAndStart()
    }

    private func requestPermissionsAndStart() {
        AVCaptureDevice.requestAccess(for: .audio) { micGranted in
            SFSpeechRecognizer.requestAuthorization { speechStatus in
                DispatchQueue.main.async {
                    if !micGranted {
                        self.listenerState = .failed("Microphone access is off. Allow HeyVoice in System Settings → Privacy & Security → Microphone.")
                    } else if speechStatus != .authorized {
                        self.listenerState = .failed("Speech recognition is off. Allow HeyVoice in System Settings → Privacy & Security → Speech Recognition.")
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
                    self.listener.watchForSend()
                    self.updateIcon()
                }
            }
        }
    }

    private func sendClaudeCodePrompt() {
        NSSound(named: "Pop")?.play()
        launcher.finishClaudeCodeDictation { [weak self] result in
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
        case ("send", "claude-code"):
            listener.cancelSendWatch()
            sendClaudeCodePrompt()
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
        listener.cancelSendWatch()
        sendClaudeCodePrompt()
    }

    @objc private func stopWaitingForSend() { listener.cancelSendWatch() }

    @objc private func dumpClaude() {
        launcher.dumpClaudeControls { result in
            DispatchQueue.main.async { self.lastAction = result }
        }
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleServerRecognition() {
        allowServerRecognition.toggle()
        listener.allowServerRecognition = allowServerRecognition
        listener.stop()
        if !paused { requestPermissionsAndStart() }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
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
            menu.addItem(info("Dictating to Claude Code — say “send it” to send"))
            menu.addItem(item("Send Now", #selector(sendNow)))
            menu.addItem(item("Stop Waiting for “Send It”", #selector(stopWaitingForSend)))
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
        if !AXIsProcessTrusted() {
            menu.addItem(item("Grant Accessibility Permission…", #selector(openAccessibilitySettings)))
        }
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let server = item("Allow Online Speech Recognition", #selector(toggleServerRecognition))
        server.state = allowServerRecognition ? .on : .off
        server.toolTip = "Only used if on-device recognition is unavailable. Sends microphone audio to Apple."
        menu.addItem(server)

        menu.addItem(.separator())
        menu.addItem(item("Quit HeyVoice", #selector(quit), key: "q"))
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
        var symbol: String
        if Date() < flashUntil {
            symbol = "waveform.circle.fill"
        } else if paused {
            symbol = "waveform.slash"
        } else if case .failed = listenerState {
            symbol = "exclamationmark.triangle"
        } else {
            symbol = "waveform"
        }
        if listener.isWatchingForSend && Date() >= flashUntil { symbol = "text.bubble" }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "HeyVoice")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }
}
