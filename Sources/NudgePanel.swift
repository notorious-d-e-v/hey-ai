import AppKit

/// A small "Done?" bubble shown just above Claude Code's prompt box when you pause while
/// dictating. It never takes focus or clicks, so dictation carries on underneath it.
final class NudgePanel {
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")

    /// `anchor` is a screen frame with a top-left origin, as Accessibility reports it.
    func show(_ text: String, above anchor: CGRect?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 28, height: label.frame.height + 16)
        label.setFrameOrigin(NSPoint(x: 14, y: 8))

        let origin: NSPoint
        if let anchor, let primary = NSScreen.screens.first {
            // Flip to AppKit's bottom-left origin and sit 8 pt above the prompt box.
            origin = NSPoint(x: anchor.midX - size.width / 2,
                             y: primary.frame.maxY - anchor.minY + 8)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? .zero
            origin = NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 12)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        panel.contentView = background

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        background.addSubview(label)
        return panel
    }
}
