import AppKit
import SwiftUI

// Renders the setup window and nudge in each state to PNGs, for design review.
// Build: see tools/snapshot.sh

let out = CommandLine.arguments.dropFirst().first ?? "/tmp/heyai-snapshots"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func render<V: View>(_ view: V, _ name: String) {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
    let size = host.fittingSize
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = .white
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    print("\(name): \(Int(size.width))x\(Int(size.height))")
}

let fresh = SetupModel()
fresh.microphone = .needed; fresh.speech = .needed; fresh.accessibility = .needed; fresh.onDeviceSpeech = true
render(SetupView(model: fresh), "setup-1-fresh")

let partial = SetupModel()
partial.microphone = .granted; partial.speech = .denied; partial.accessibility = .needed; partial.asking = true
render(SetupView(model: partial), "setup-2-partial")

let ready = SetupModel()
ready.microphone = .granted; ready.speech = .granted; ready.accessibility = .granted
render(SetupView(model: ready), "setup-3-ready")

let heard = SetupModel()
heard.microphone = .granted; heard.speech = .granted; heard.accessibility = .granted
heard.lastHeard = "Heard “Hey Claude”. Opening Claude…"
render(SetupView(model: heard), "setup-4-heard")

render(NudgePreview(), "nudge")
