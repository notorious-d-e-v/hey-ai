import AppKit
import ApplicationServices

/// Which ChatGPT desktop app "Hey Chatty" opens.
enum ChatGPTApp: String, CaseIterable {
    /// "ChatGPT" — the current ChatGPT + Codex desktop app.
    case unified
    /// "ChatGPT Classic" — the older native ChatGPT app.
    case classic

    var bundleID: String { self == .unified ? "com.openai.codex" : "com.openai.chat" }
    var menuTitle: String { self == .unified ? "ChatGPT (ChatGPT + Codex app)" : "ChatGPT Classic" }
    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
}

/// Opens an assistant straight into a new voice conversation.
///
/// - ChatGPT (new app): bring it forward, ⌘N for a new chat, then ⌃⇧V — the app's own
///   "start voice chat" shortcut.
/// - ChatGPT Classic: the app's `chatgpt://new-voice-conversation` link.
/// - Claude: `claude://claude.ai/new` opens a new chat, then the composer's "Use voice mode"
///   button is pressed through Accessibility. (Older claude.ai builds left that button
///   unlabeled; then it is the rightmost unlabeled button in the composer's bottom row.)
final class Launcher {
    static let claudeBundleID = "com.anthropic.claudefordesktop"

    private let queue = DispatchQueue(label: "heyvoice.launcher")

    /// Runs off the main thread; `completion` gets a one-line result for the menu and log.
    func open(_ target: WakeTarget, chatGPT: ChatGPTApp, completion: @escaping (String) -> Void) {
        queue.async {
            let result: String
            switch target {
            case .chatgpt:
                result = chatGPT == .classic ? self.openChatGPTClassic() : self.openChatGPTUnified()
            case .claude:
                result = self.openClaudeVoice()
            }
            completion(result)
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

    // MARK: ChatGPT

    private func openChatGPTClassic() -> String {
        guard ChatGPTApp.classic.isInstalled else { return "ChatGPT Classic isn't installed" }
        let url = URL(string: "chatgpt://new-voice-conversation")!
        return Self.openURL(url) ? "ChatGPT Classic: started a new voice conversation"
                                 : "ChatGPT Classic didn't accept the voice link"
    }

    private func openChatGPTUnified() -> String {
        let bundleID = ChatGPTApp.unified.bundleID
        guard ChatGPTApp.unified.isInstalled else { return "ChatGPT isn't installed" }
        guard AXIsProcessTrusted() else {
            _ = Self.activate(bundleID)
            return "ChatGPT: opened, but HeyVoice needs Accessibility permission to start voice"
        }
        let wasRunning = Self.running(bundleID) != nil
        guard Self.activate(bundleID),
              Self.waitUntilFrontmost(bundleID, timeout: wasRunning ? 8 : 25) else {
            return "ChatGPT didn't come to the front"
        }
        // A cold-launched app needs a moment before its shortcuts are wired up.
        Thread.sleep(forTimeInterval: wasRunning ? 0.3 : 3)

        guard Self.isFrontmost(bundleID) else { return "ChatGPT lost focus before voice could start" }
        Keys.press(Keys.n, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 1.0)
        guard Self.isFrontmost(bundleID) else { return "ChatGPT lost focus before voice could start" }
        Keys.press(Keys.v, flags: [.maskControl, .maskShift])
        return "ChatGPT: new chat + voice shortcut sent"
    }

    // MARK: Claude

    private func openClaudeVoice() -> String {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeBundleID) != nil else {
            return "Claude isn't installed"
        }
        guard Self.openURL(URL(string: "claude://claude.ai/new")!) else { return "Claude didn't open a new chat" }
        guard AXIsProcessTrusted() else {
            return "Claude: opened a new chat, but HeyVoice needs Accessibility permission to start voice"
        }
        guard let app = Self.waitUntilRunning(Self.claudeBundleID, timeout: 25) else {
            return "Claude didn't start"
        }
        _ = Self.activate(Self.claudeBundleID)

        let reader = AXReader(pid: app.processIdentifier)
        Log.info("Claude: AXManualAccessibility → \(reader.enableWebAccessibility().rawValue)")

        let start = Date()
        let deadline = start.addingTimeInterval(20)
        var enhanced = false
        while Date() < deadline {
            let elapsed = Date().timeIntervalSince(start)
            // Some Chromium builds only expose page content to assistive apps that set this.
            if !enhanced && elapsed > 3 {
                enhanced = true
                Log.info("Claude: AXEnhancedUserInterface → \(reader.enableEnhancedUserInterface().rawValue)")
            }
            // Until the page reports /new, the old page (and its buttons) may still be up.
            let allowAnyClaudePage = elapsed > 8
            if let composer = reader.findComposer(requireNewChat: !allowAnyClaudePage),
               let button = composer.voiceButtonCandidates.first {
                Log.info("Claude: pressing voice button at \(button.frame) (\(composer.voiceButtonCandidates.count) candidates)")
                reader.press(button.element)
                if reader.waitForVoiceModeStart(near: composer, timeout: 5) {
                    return "Claude: voice mode started"
                }
                return "Claude: pressed the voice button (couldn't confirm voice started)"
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        let lines = reader.describeControls()
        Log.info("Claude: voice button not found. Controls seen:\n" + lines.joined(separator: "\n"))
        return "Claude: opened a new chat but couldn't find the voice button"
    }

    // MARK: App helpers

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
    static let n: CGKeyCode = 45 // kVK_ANSI_N
    static let v: CGKeyCode = 9  // kVK_ANSI_V

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

    @discardableResult
    func enableEnhancedUserInterface() -> AXError {
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
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

    private func windows() -> [AXUIElement] {
        (copy(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
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
