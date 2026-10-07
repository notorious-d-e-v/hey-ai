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
    @Published var asking = false
    @Published var launchAtLogin = true
    /// What Hey AI just did, shown on the "try it" screen.
    @Published var lastHeard: String?

    var allGranted: Bool { microphone == .granted && speech == .granted && accessibility == .granted }
    var canListen: Bool { microphone == .granted && speech == .granted }

    /// Called once microphone and speech are allowed, so listening can start right away.
    var onCanListen: (() -> Void)?
    var onFinish: (() -> Void)?

    private var accessibilityTimer: Timer?
    private var refreshTimer: Timer?

    init() { refresh() }

    /// While the window is open, pick up permissions switched on in System Settings.
    func startWatching() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let couldListen = self.canListen
            self.refresh()
            if !couldListen && self.canListen { self.onCanListen?() }
            if self.allGranted { self.asking = false }
        }
    }

    func stopWatching() {
        refreshTimer?.invalidate()
        accessibilityTimer?.invalidate()
    }

    func refresh() {
        let mic = Self.status(AVCaptureDevice.authorizationStatus(for: .audio))
        let spe = Self.status(SFSpeechRecognizer.authorizationStatus())
        let ax: Status = AXIsProcessTrusted() ? .granted : .needed
        // Only publish real changes, so SwiftUI doesn't redraw every second.
        if mic != microphone { microphone = mic }
        if spe != speech { speech = spe }
        if ax != accessibility { accessibility = ax }
        let onDevice = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false
        if onDevice != onDeviceSpeech { onDeviceSpeech = onDevice }
    }

    /// The one button: microphone, then speech recognition, then Accessibility.
    func allowAccess() {
        asking = true
        requestMicrophone { [weak self] in
            self?.requestSpeech {
                guard let self else { return }
                if self.canListen { self.onCanListen?() }
                self.requestAccessibility()
            }
        }
    }

    private func requestMicrophone(then next: @escaping () -> Void) {
        guard microphone != .granted else { return next() }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.microphone = granted ? .granted : .denied
                next()
            }
        }
    }

    private func requestSpeech(then next: @escaping () -> Void) {
        guard speech != .granted else { return next() }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.speech = status == .authorized ? .granted : .denied
                self.onDeviceSpeech = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false
                next()
            }
        }
    }

    /// macOS can't grant this from a prompt: it adds Hey AI to the Accessibility list and
    /// you switch it on. Poll until it's on, then come back to the front.
    private func requestAccessibility() {
        guard !AXIsProcessTrusted() else {
            accessibility = .granted
            asking = false
            return
        }
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.accessibility = .granted
            self?.asking = false
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
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
    static var claude: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Launcher.claudeBundleID) != nil }
    static var chatGPT: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Launcher.codexBundleID) != nil }
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

            PermissionRow(step: 1, title: "Microphone", detail: "Hears the wake phrase. Nothing is recorded or sent anywhere.",
                          status: model.microphone) { model.openSettings("Privacy_Microphone") }
            PermissionRow(step: 2, title: "Speech recognition", detail: "Turns what you say into text, on this Mac.",
                          status: model.speech) { model.openSettings("Privacy_SpeechRecognition") }
            PermissionRow(step: 3, title: "Accessibility", detail: "Lets Hey AI press the voice button in Claude and ChatGPT. Switch on Hey AI in the list that opens.",
                          status: model.asking && model.accessibility != .granted ? .denied : model.accessibility,
                          linkTitle: model.asking ? "Open Accessibility settings" : "Turn it on in System Settings") {
                model.openSettings("Privacy_Accessibility")
            }

            if model.speech == .granted && !model.onDeviceSpeech {
                Text("On-device speech isn't downloaded yet. Turn on Dictation in System Settings → Keyboard and macOS downloads it.")
                    .font(.system(size: 12))
                    .foregroundColor(Brand.graphite)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }

            Button(action: model.allowAccess) {
                HStack(spacing: 8) {
                    if model.asking { ProgressView().controlSize(.small).colorScheme(.dark) }
                    Text(model.asking ? "Waiting for Accessibility" : "Allow access")
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(Brand.ink.opacity(model.asking ? 0.7 : 1)))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(model.asking)
            .padding(.top, 16)
        }
    }
}

private struct PermissionRow: View {
    let step: Int
    let title: String
    let detail: String
    let status: SetupModel.Status
    var linkTitle = "Turn it on in System Settings"
    let openSettings: () -> Void

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
                Text(detail).font(.system(size: 12.5)).foregroundColor(Brand.graphite)
                    .fixedSize(horizontal: false, vertical: true)
                if status == .denied {
                    Button(linkTitle, action: openSettings)
                        .buttonStyle(.link)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Brand.signal)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
    }
}

private struct ReadyView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You're set. Try one now.")
                .font(.system(size: 20, weight: .bold))
                .padding(.bottom, 16)

            if Assistants.claude {
                PhraseRow(phrase: "Hey Claude", opens: "Claude, in voice mode")
                PhraseRow(phrase: "Hey Claude Code", opens: "A new Claude Code session, dictating")
            } else {
                MissingRow(app: "Claude", url: "https://claude.ai/download")
            }
            if Assistants.chatGPT {
                PhraseRow(phrase: "Hey Chatty", opens: "ChatGPT, in voice mode")
                PhraseRow(phrase: "Hey Codex", opens: "Codex, in voice mode")
            } else {
                MissingRow(app: "ChatGPT", url: "https://openai.com/chatgpt/download/")
            }

            HStack(spacing: 8) {
                Circle().fill(Brand.signal).frame(width: 7, height: 7)
                Text(model.lastHeard ?? "Listening")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(model.lastHeard == nil ? Brand.graphite : Brand.signal)
            }
            .padding(.top, 8)
            .padding(.bottom, 18)

            PhraseRow(phrase: "stop listening", opens: "Ends a voice chat", compact: true)
            PhraseRow(phrase: "send it", opens: "Sends what you dictated to Claude Code", compact: true)
                .padding(.bottom, 12)

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

private struct MissingRow: View {
    let app: String
    let url: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(app) isn't installed.").font(.system(size: 13)).foregroundColor(Brand.graphite)
            Button("Get \(app)") { NSWorkspace.shared.open(URL(string: url)!) }
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
        window.isMovableByWindowBackground = true
        window.backgroundColor = .white
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: SetupView(model: model))
        window.setContentSize(window.contentView!.fittingSize)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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
        frame.origin.y += frame.height - window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).height
        frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        window.setFrame(frame, display: true, animate: true)
    }
}
