import AVFoundation
import Foundation
import Speech

/// Keeps the microphone open and runs Apple's speech recognizer over it, looking for a
/// wake phrase in every partial transcript. Recognition tasks are rotated every 50 s (and
/// right after a wake) so transcripts stay short and an old phrase can never fire twice.
final class WakeListener {
    enum State: Equatable {
        case stopped
        case listening(onDevice: Bool)
        case failed(String)
    }

    var onWake: ((WakeMatch, String) -> Void)?
    var onHeard: ((String) -> Void)?
    var onState: ((State) -> Void)?
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

    private static let rotateInterval: TimeInterval = 50
    private static let cooldown: TimeInterval = 3

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

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        newRequest.contextualStrings = ["Hey Chatty", "Hey Claude", "Chatty", "Claude"]
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
            if Date() >= cooldownUntil, let match = firstMatch(in: result) {
                cooldownUntil = Date().addingTimeInterval(Self.cooldown)
                onWake?(match, text)
                startTask()
                return
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
