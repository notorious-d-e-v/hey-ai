import CoreAudio
import Foundation

/// Asks Core Audio which processes are capturing microphone input, to tell when one of
/// the assistant apps is already listening (a voice chat or a dictation is open).
enum MicActivity {
    enum Assistant: String {
        case claude = "Claude"
        case chatgpt = "ChatGPT"
        case chatgptClassic = "ChatGPT Classic"

        /// Bundle-ID prefix, so helper processes count too: Electron apps capture audio in
        /// a helper such as "com.anthropic.claudefordesktop.helper".
        var bundlePrefix: String {
            switch self {
            case .claude: return "com.anthropic.claudefordesktop"
            case .chatgpt: return "com.openai.codex"
            case .chatgptClassic: return "com.openai.chat"
            }
        }
    }

    static let all: [Assistant] = [.claude, .chatgpt, .chatgptClassic]

    /// An assistant app that is using the microphone right now, if any.
    static func assistantListening() -> Assistant? {
        let listening = assistantsListening()
        return all.first { listening.contains($0) }
    }

    /// Every assistant app using the microphone right now. Two can at once, say a ChatGPT
    /// voice chat while you dictate to Claude.
    static func assistantsListening() -> Set<Assistant> {
        guard #available(macOS 14.0, *) else { return [] }
        var found: Set<Assistant> = []
        for process in processObjects() where isRunningInput(process) {
            guard let bundleID = bundleID(of: process) else { continue }
            if let match = all.first(where: { bundleID.hasPrefix($0.bundlePrefix) }) { found.insert(match) }
        }
        return found
    }

    static func isListening(_ assistant: Assistant) -> Bool {
        assistantsListening().contains(assistant)
    }

    @available(macOS 14.0, *)
    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    @available(macOS 14.0, *)
    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    @available(macOS 14.0, *)
    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }
}
