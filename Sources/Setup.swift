import AppKit
import ApplicationServices
import AVFoundation
import Speech
import SwiftUI

/// State behind the first-run window: the three permissions Hey AI needs, asked for in
/// one pass, then a live "try it" screen.
final class SetupModel: ObservableObject {
    enum Status { case needed, granted, denied }

    @Published var microphone: Status = .needed
    @Published var speech: Status = .needed
    @Published var accessibility: Status = .needed
    @Published var onDeviceSpeech = true
    /// The Accessibility prompt has been shown; waiting for the switch in System Settings.
    @Published var askedAccessibility = false
    @Published var launchAtLogin = true
    /// What Hey AI just did, shown on the "try it" screen.
    @Published var lastHeard: String?
    /// Why Hey AI isn't listening, if it isn't.
    @Published var listenerProblem: String?
    /// macOS hid the menu-bar icon (the menu bar is full).
    @Published var menuBarIconHidden = false
    /// Whether the microphone is actually being listened to right now.
    @Published var isListening = false
    @Published var isPaused = false
    /// Hey AI added ChatGPT's voice hotkey, and ChatGPT has to restart to pick it up.
    @Published var chatgptNeedsRestart = false

    var allGranted: Bool { microphone == .granted && speech == .granted && accessibility == .granted }
    var canListen: Bool { microphone == .granted && speech == .granted }

    /// Called whenever microphone and speech are allowed (on every refresh while the window
    /// is open), so listening starts, or restarts after Dictation is turned on.
    var onCanListen: (() -> Void)?
    var onFinish: (() -> Void)?
    var onRestartChatGPT: (() -> Void)?
    /// The window was closed with its close button.
    var onClose: (() -> Void)?

    private var refreshTimer: Timer?
    private var shownAt = Date()

    init() { refresh() }

    func refresh() {
        let mic = Self.status(AVCaptureDevice.authorizationStatus(for: .audio))
        let spe = Self.status(SFSpeechRecognizer.authorizationStatus())
        let ax: Status = AXIsProcessTrusted() ? .granted : .needed
        // Only publish real changes, so SwiftUI doesn't redraw every second.
        if mic != microphone { microphone = mic }
        if spe != speech { speech = spe }
        if ax != accessibility {
            accessibility = ax
            if ax == .granted && askedAccessibility {
                logStep("Accessibility allowed")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        let onDevice = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false
        if onDevice != onDeviceSpeech { onDeviceSpeech = onDevice }
    }

    /// While the window is open, pick up permissions switched on in System Settings.
    func startWatching() {
        shownAt = Date()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refresh()
            if self.canListen { self.onCanListen?() }
        }
        if canListen { onCanListen?() }
    }

    func stopWatching() {
        refreshTimer?.invalidate()
    }

    // MARK: The one button

    enum Action { case allow, openMicrophone, openSpeech, openAccessibility }

    /// Worked out from the current state, so the button always does something useful.
    var action: Action {
        if microphone == .denied { return .openMicrophone }
        if speech == .denied { return .openSpeech }
        if askedAccessibility && accessibility != .granted { return .openAccessibility }
        return .allow
    }

    var actionTitle: String {
        switch action {
        case .allow: return "Allow access"
        case .openMicrophone: return "Open Microphone settings"
        case .openSpeech: return "Open Speech Recognition settings"
        case .openAccessibility: return "Open Accessibility settings"
        }
    }

    func perform() {
        switch action {
        case .allow: allowAccess()
        case .openMicrophone: openSettings("Privacy_Microphone")
        case .openSpeech: openSettings("Privacy_SpeechRecognition")
        case .openAccessibility: openSettings("Privacy_Accessibility")
        }
    }

    /// Microphone, then speech recognition, then Accessibility.
    private func allowAccess() {
        logStep("Allow access clicked")
        requestMicrophone { [weak self] in
            self?.requestSpeech {
                guard let self, self.canListen else { return }
                self.onCanListen?()
                self.requestAccessibility()
            }
        }
    }

    private func requestMicrophone(then next: @escaping () -> Void) {
        guard microphone != .granted else { return next() }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.microphone = granted ? .granted : .denied
                self.logStep("microphone \(granted ? "allowed" : "denied")")
                next()
            }
        }
    }

    private func requestSpeech(then next: @escaping () -> Void) {
        guard speech != .granted else { return next() }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.speech = status == .authorized ? .granted : .denied
                self.logStep("speech recognition \(status == .authorized ? "allowed" : "denied")")
                self.onDeviceSpeech = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false
                next()
            }
        }
    }

    /// macOS can't grant this from a prompt: it adds Hey AI to the Accessibility list and
    /// you switch it on. The refresh timer notices and brings the window back.
    private func requestAccessibility() {
        guard !AXIsProcessTrusted() else {
            accessibility = .granted
            return
        }
        askedAccessibility = true
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    private func logStep(_ step: String) {
        Log.info(String(format: "setup: %@ (%.1f s after the window opened)", step, Date().timeIntervalSince(shownAt)))
    }

    private static func status(_ s: AVAuthorizationStatus) -> Status {
        switch s {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .needed
        }
    }

    private static func status(_ s: SFSpeechRecognizerAuthorizationStatus) -> Status {
        switch s {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .needed
        }
    }
}

/// Which assistants are installed, for the "try it" list.
struct Assistants {
    static var claude: Bool { installed(Launcher.claudeBundleID) }
    /// The current ChatGPT app (it includes Codex).
    static var chatGPT: Bool { installed(Launcher.codexBundleID) }
    /// Only the older ChatGPT app, which has no voice mode Hey AI can start.
    static var chatGPTClassicOnly: Bool { !chatGPT && installed("com.openai.chat") }

    private static func installed(_ id: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark().fill(Brand.ink).frame(width: 30, height: 22)
                BrandWordmark().fill(Brand.ink).frame(width: 22 * Brand.wordmarkAspect, height: 22)
            }
            .padding(.bottom, 14)

            if model.allGranted {
                ReadyView(model: model)
            } else {
                PermissionsView(model: model)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 480, alignment: .leading)
        .background(Brand.paper)
        .foregroundColor(Brand.ink)
    }
}

private struct PermissionsView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Allow three things, once.")
                .font(.system(size: 20, weight: .bold))
                .padding(.bottom, 4)
            Text("Then say an assistant's name and it opens, ready to talk.")
                .font(.system(size: 13))
                .foregroundColor(Brand.graphite)
                .padding(.bottom, 20)

            PermissionRow(step: 1, title: "Microphone", detail: "Hears the wake phrase. Nothing is recorded.",
                          status: model.microphone)
            PermissionRow(step: 2, title: "Speech recognition", detail: "Turns what you say into text, on this Mac.",
                          status: model.speech)
            PermissionRow(step: 3, title: "Accessibility",
                          detail: "Lets Hey AI open a new chat and start voice in ChatGPT and Claude.",
                          status: model.accessibility)

            if model.speech == .granted && !model.onDeviceSpeech {
                Note("On-device speech isn't downloaded yet. Turn on Dictation in System Settings → Keyboard and macOS downloads it.")
            }

            if model.action == .openAccessibility {
                HStack(alignment: .top, spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Switch on Hey AI in the list, then come back here. macOS may ask for your password.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Brand.graphite)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)
            }

            Button(action: model.perform) {
                Text(model.actionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Brand.ink))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 12)
        }
    }
}

private struct PermissionRow: View {
    let step: Int
    let title: String
    let detail: String
    let status: SetupModel.Status

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(status == .granted ? Brand.ink : Brand.mist).frame(width: 24, height: 24)
                if status == .granted {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(Brand.highlight)
                } else {
                    Text("\(step)").font(.system(size: 12, weight: .semibold)).foregroundColor(Brand.graphite)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(status == .denied ? "Turned off. The button below opens the setting." : detail)
                    .font(.system(size: 12.5))
                    .foregroundColor(Brand.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
    }
}

private struct ReadyView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        let hasAssistant = Assistants.claude || Assistants.chatGPT
        VStack(alignment: .leading, spacing: 0) {
            Text(model.listenerProblem != nil || model.isPaused ? "One more step."
                 : hasAssistant ? "You're set. Try one now." : "Almost there. Install an assistant.")
                .font(.system(size: 20, weight: .bold))
                .padding(.bottom, 8)

            StatusLine(model: model)
                .padding(.bottom, 16)

            if Assistants.chatGPT {
                PhraseRow(phrase: "Hey Chatty", opens: "ChatGPT, in voice mode")
                PhraseRow(phrase: "Hey Codex", opens: "The same voice chat")
                if model.chatgptNeedsRestart {
                    RestartChatGPTRow(model: model)
                }
            } else if Assistants.chatGPTClassicOnly {
                MissingRow(text: "Your ChatGPT app is the older version.", link: "Get the new one",
                           url: "https://openai.com/chatgpt/download/")
            } else {
                MissingRow(text: "ChatGPT isn't installed.", link: "Get ChatGPT", url: "https://openai.com/chatgpt/download/")
            }
            if Assistants.claude {
                PhraseRow(phrase: "Hey Claude", opens: "Claude, in voice mode")
                PhraseRow(phrase: "Hey Claude Code", opens: "A new Claude Code session, dictating")
            } else {
                MissingRow(text: "Claude isn't installed.", link: "Get Claude", url: "https://claude.ai/download")
            }

            PhraseRow(phrase: "stop listening", opens: "Ends a voice chat", compact: true)
                .padding(.top, 8)
            PhraseRow(phrase: "send it", opens: "Sends what you dictated to Claude Code", compact: true)
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 8) {
                BrandMark().fill(Brand.ink).frame(width: 15, height: 11).padding(.top, 3)
                Text(model.menuBarIconHidden
                     ? "Your menu bar is full, so macOS is hiding Hey AI's quote mark behind the notch. Hold ⌘ and drag a few icons off the menu bar to make room. Hey AI keeps listening either way."
                     : "Hey AI lives in your menu bar. Click the quote mark to pause it or quit.")
                    .font(.system(size: 12.5))
                    .foregroundColor(Brand.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 16)

            Toggle("Start Hey AI when you log in", isOn: $model.launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .padding(.bottom, 18)

            Button(action: { model.onFinish?() }) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Brand.ink))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// "Listening", what was just heard, or why it isn't listening.
private struct StatusLine: View {
    @ObservedObject var model: SetupModel

    private var text: String {
        if let problem = model.listenerProblem { return "Not listening. \(problem)" }
        if model.isPaused { return "Paused. Resume from the menu bar." }
        if !model.isListening { return "Starting…" }
        return model.lastHeard ?? "Listening"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(model.isListening ? Brand.signal : Color.clear)
                .overlay(Circle().stroke(model.isListening ? Color.clear : Brand.graphite, lineWidth: 1.5))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(model.lastHeard != nil && model.isListening ? Brand.signal : Brand.graphite)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Brand.graphite)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)
    }
}

/// A wake phrase, highlighted the way the brand marks words you say out loud.
private struct PhraseRow: View {
    let phrase: String
    let opens: String
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("“\(phrase)”")
                .font(.system(size: compact ? 13 : 15, weight: compact ? .semibold : .bold))
                .padding(.horizontal, compact ? 5 : 6)
                .padding(.vertical, compact ? 1 : 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Brand.highlight))
            Text(opens).font(.system(size: compact ? 12.5 : 13)).foregroundColor(Brand.graphite)
            Spacer(minLength: 0)
        }
        .padding(.bottom, compact ? 6 : 10)
    }
}

/// Hey AI turned on ChatGPT's voice hotkey, which ChatGPT reads when it starts.
private struct RestartChatGPTRow: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hey AI turned on ChatGPT's voice hotkey (\(ChatGPTHotkey.defaultKeySymbols)), so it can start ChatGPT voice from any app. It kicks in when ChatGPT restarts.")
                .font(.system(size: 12.5))
                .foregroundColor(Brand.graphite)
                .fixedSize(horizontal: false, vertical: true)
            Button("Restart ChatGPT now") { model.onRestartChatGPT?() }
                .buttonStyle(.link)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Brand.signal)
        }
        .padding(.bottom, 12)
    }
}

private struct MissingRow: View {
    let text: String
    let link: String
    let url: String

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 13)).foregroundColor(Brand.graphite)
            Button(link) { NSWorkspace.shared.open(URL(string: url)!) }
                .buttonStyle(.link)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Brand.signal)
        }
        .padding(.bottom, 10)
    }
}

/// The first-run window.
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    let model: SetupModel

    init(model: SetupModel) {
        self.model = model
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Hey AI"
        window.isMovableByWindowBackground = true
        window.backgroundColor = .white
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: SetupView(model: model))
        window.setContentSize(window.contentView!.fittingSize)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        model.onClose?()
    }

    func present() {
        model.refresh()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Keep the window sized to its content as the steps change.
    func resizeToFit() {
        guard let window, let content = window.contentView else { return }
        let size = content.fittingSize
        var frame = window.frame
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        guard abs(target.height - frame.height) > 0.5 else { return }
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: true)
    }
}
