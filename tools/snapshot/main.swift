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

// Menu-bar icon states, drawn by the app's own code, at 4x on transparent.
let logoDir = CommandLine.arguments.dropFirst(2).first
if let logoDir {
    let states: [(String, Brand.MenuState)] = [("listening", .listening), ("paused", .paused), ("heard", .heard), ("dictating", .dictating)]
    for (name, state) in states {
        let image = Brand.menuBarImage(state)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 24, height: 16)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 16))
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(logoDir)/menubar-\(name).png"))
        print("menubar-\(name)")
    }
}
