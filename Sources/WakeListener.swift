import AVFoundation
import Foundation
import Speech

/// Keeps the microphone open and runs Apple's speech recognizer over it, looking for a
/// wake phrase in every partial transcript. Recognition tasks are rotated every 50 s (and
/// right after a wake) so transcripts stay short and an old phrase can never fire twice.
///
/// While a Claude Code dictation is open it instead waits for "send it" to end the
/// transcript, and wake phrases are ignored so dictated text can't launch anything.
final class WakeListener {
    enum State: Equatable {
        case stopped
        case listening(onDevice: Bool)
        case failed(String)
    }

    var onWake: ((WakeMatch, String) -> Void)?
    var onHeard: ((String) -> Void)?
    var onState: ((State) -> Void)?
    /// "send it" ended the transcript while watching for it.
    var onSendPhrase: (() -> Void)?
    /// The send watch ended without "send it" (timeout or long silence).
    var onSendWatchEnded: ((String) -> Void)?
    /// Use Apple's servers when on-device recognition isn't available. Off by default,
    /// because it would stream the always-on microphone to Apple.
    var allowServerRecognition = false

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let requestLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var rotateTimer: Timer?
    private var cooldownUntil = Date.distantPast
    private var consecutiveErrors = 0
    private var configObserver: NSObjectProtocol?
    private(set) var isRunning = false

    /// "hey claude" heard as the last words, held briefly in case "code" follows.
    private var pendingMatch: (match: WakeMatch, text: String)?
    private var pendingTimer: Timer?

    private(set) var isWatchingForSend = false
    private var sendWatchStarted = Date.distantPast
    private var lastHeardChange = Date.distantPast
    private var lastHeardText = ""
    private var sendTimer: Timer?
    private var sendWatchTimer: Timer?

    private static let rotateInterval: TimeInterval = 50
    private static let cooldown: TimeInterval = 3
    private static let continuationWait: TimeInterval = 0.8
    /// Silence after "send it" before it counts, so "send it to the API…" doesn't fire.
    private static let sendSettle: TimeInterval = 1.0
    private static let sendWatchLimit: TimeInterval = 300
    private static let sendWatchSilenceLimit: TimeInterval = 90

    /// Start waiting for "send it" (after Claude Code dictation has started).
    func watchForSend() {
        isWatchingForSend = true
        sendWatchStarted = Date()
        lastHeardChange = Date()
        sendWatchTimer?.invalidate()
        sendWatchTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isWatchingForSend else { return }
            if Date().timeIntervalSince(self.sendWatchStarted) > Self.sendWatchLimit {
                self.endSendWatch("stopped waiting for “send it” after 5 minutes")
            } else if Date().timeIntervalSince(self.lastHeardChange) > Self.sendWatchSilenceLimit {
                self.endSendWatch("stopped waiting for “send it” after 90 s of silence")
            }
        }
        startTask()
    }

    func cancelSendWatch() {
        endSendWatch("stopped waiting for “send it”")
    }

    private func endSendWatch(_ reason: String) {
        guard isWatchingForSend else { return }
        isWatchingForSend = false
        sendTimer?.invalidate()
        sendWatchTimer?.invalidate()
        onSendWatchEnded?(reason)
    }

    func start() {
        guard !isRunning else { return }
        guard let recognizer else { return fail("Speech recognition doesn't support English (US) on this Mac") }
        let onDevice = recognizer.supportsOnDeviceRecognition
        if !onDevice && !allowServerRecognition {
            return fail("On-device speech recognition isn't available. Turn on Dictation in System Settings → Keyboard so macOS downloads it.")
        }
        do {
            try startEngine()
        } catch {
            return fail("Microphone error: \(error.localizedDescription)")
        }
        isRunning = true
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restartEngine(attempt: 1) }
        startTask()
        Log.info("listening (on-device: \(onDevice))")
        onState?(.listening(onDevice: onDevice))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        rotateTimer?.invalidate()
        pendingTimer?.invalidate()
        pendingMatch = nil
        endSendWatch("stopped listening")
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        requestLock.lock()
        request?.endAudio()
        request = nil
        requestLock.unlock()
        task?.cancel()
        task = nil
        Log.info("stopped listening")
        onState?(.stopped)
    }

    private func fail(_ message: String) {
        Log.info("listener failed: \(message)")
        if isRunning { stop() }
        onState?(.failed(message))
    }

    // MARK: Audio

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "HeyVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no microphone input is available"])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.requestLock.lock()
            self.request?.append(buffer)
            self.requestLock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    /// Input device changed (headphones plugged in, another app reconfigured audio, …).
    private func restartEngine(attempt: Int) {
        guard isRunning else { return }
        Log.info("audio configuration changed; restarting microphone (attempt \(attempt))")
        engine.stop()
        do {
            try startEngine()
            startTask()
        } catch {
            guard attempt < 5 else { return fail("Microphone error: \(error.localizedDescription)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.restartEngine(attempt: attempt + 1)
            }
        }
    }

    // MARK: Recognition

    private func startTask() {
        guard isRunning, let recognizer else { return }
        generation += 1
        let gen = generation
        lastHeardText = ""

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        newRequest.contextualStrings = isWatchingForSend
            ? ["send it"]
            : ["Hey Chatty", "Hey Codex", "Hey Claude", "Hey Claude Code", "Chatty", "Codex", "Claude"]
        newRequest.addsPunctuation = false

        requestLock.lock()
        let oldRequest = request
        request = newRequest
        requestLock.unlock()
        oldRequest?.endAudio()
        task?.cancel()

        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            DispatchQueue.main.async { self?.handle(result: result, error: error, generation: gen) }
        }
        rotateTimer?.invalidate()
        rotateTimer = Timer.scheduledTimer(withTimeInterval: Self.rotateInterval, repeats: false) { [weak self] _ in
            self?.startTask()
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation gen: Int) {
        guard gen == generation, isRunning else { return }

        if let result {
            consecutiveErrors = 0
            let text = result.bestTranscription.formattedString
            onHeard?(text)
            if text != lastHeardText {
                lastHeardText = text
                lastHeardChange = Date()
            }
            if isWatchingForSend {
                checkSendPhrase(text)
            } else if Date() >= cooldownUntil, let match = firstMatch(in: result) {
                if match.mayContinue {
                    holdForContinuation(match, text: text)
                } else {
                    fire(match, text: text)
                    return
                }
            }
            if result.isFinal { startTask() }
            return
        }

        guard let error else { return }
        let nsError = error as NSError
        // 1110 = "no speech detected" and 216/301 = task cancelled; both are routine.
        let routine = [1110, 216, 301].contains(nsError.code)
        if !routine {
            consecutiveErrors += 1
            Log.info("recognition error \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
        }
        let delay = routine ? 0.1 : min(Double(consecutiveErrors), 10)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.startTask()
        }
    }

    private func fire(_ match: WakeMatch, text: String) {
        pendingTimer?.invalidate()
        pendingMatch = nil
        cooldownUntil = Date().addingTimeInterval(Self.cooldown)
        onWake?(match, text)
        startTask()
    }

    /// "hey claude" could be the start of "hey claude code": wait a moment for the next word.
    private func holdForContinuation(_ match: WakeMatch, text: String) {
        guard pendingMatch == nil else { return }
        pendingMatch = (match, text)
        pendingTimer = Timer.scheduledTimer(withTimeInterval: Self.continuationWait, repeats: false) { [weak self] _ in
            guard let self, let pending = self.pendingMatch else { return }
            self.fire(pending.match, text: pending.text)
        }
    }

    /// Fires once "send it" has ended the transcript and nothing new was heard for a second.
    private func checkSendPhrase(_ text: String) {
        sendTimer?.invalidate()
        guard SendPhrase.ends(text) else { return }
        sendTimer = Timer.scheduledTimer(withTimeInterval: Self.sendSettle, repeats: false) { [weak self] _ in
            guard let self, self.isWatchingForSend, self.lastHeardText == text else { return }
            self.isWatchingForSend = false
            self.sendWatchTimer?.invalidate()
            self.onSendPhrase?()
            self.startTask()
        }
    }

    /// Checks the best transcription and the recognizer's runner-up guesses, since a
    /// short name like "Chatty" is often only right in an alternative.
    private func firstMatch(in result: SFSpeechRecognitionResult) -> WakeMatch? {
        if let match = WakeMatcher.match(result.bestTranscription.formattedString) { return match }
        for transcription in result.transcriptions.prefix(4) {
            if let match = WakeMatcher.match(transcription.formattedString) { return match }
        }
        return nil
    }
}
