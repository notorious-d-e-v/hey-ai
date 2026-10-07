import AppKit
import SwiftUI

/// A small "Done? Say yes to send" bubble shown just above Claude Code's prompt box when
/// you pause while dictating. It never takes focus or clicks, so dictation carries on underneath it.
final class NudgePanel {
    private var panel: NSPanel?

    /// `anchor` is a screen frame with a top-left origin, as Accessibility reports it.
    func show(above anchor: CGRect?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: 320, height: 40)

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
        panel.contentView = NSHostingView(rootView: NudgeView())
        return panel
    }
}

private struct NudgeView: View {
    var body: some View {
        HStack(spacing: 6) {
            BrandMark().fill(Brand.ink).frame(width: 16, height: 12).padding(.trailing, 4)
            Text("Done? Say")
            Spoken("yes")
            Text("to send, or keep talking.")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(Brand.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))
        )
        .padding(2)
    }
}

/// Words to say out loud, highlighted per the brand.
private struct Spoken: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Brand.highlight))
    }
}

#if SNAPSHOT
/// The nudge as it appears on screen, for tools/snapshot.sh.
struct NudgePreview: View {
    var body: some View { NudgeView().padding(12).background(Color(white: 0.93)) }
}
#endif
