import CoreAudio
import Foundation

/// Asks Core Audio which processes are capturing microphone input, to tell when one of
/// the assistant apps is already listening (a voice chat or a dictation is open).
enum MicActivity {
    /// Bundle-ID prefixes, so helper processes count too: Electron apps capture audio in a
    /// helper such as "com.anthropic.claudefordesktop.helper".
    private static let assistants: [(prefix: String, name: String)] = [
        ("com.anthropic.claudefordesktop", "Claude"),
        ("com.openai.codex", "ChatGPT"),
        ("com.openai.chat", "ChatGPT Classic"),
    ]

    /// The name of an assistant app that is using the microphone right now, if any.
    static func assistantListening() -> String? {
        guard #available(macOS 14.0, *) else { return nil }
        for process in processObjects() where isRunningInput(process) {
            guard let bundleID = bundleID(of: process) else { continue }
            if let match = assistants.first(where: { bundleID.hasPrefix($0.prefix) }) { return match.name }
        }
        return nil
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
