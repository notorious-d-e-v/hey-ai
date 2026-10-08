import AppKit
import SwiftUI

/// The top of the menu-bar menu: the app icon and wordmark, the way macOS's own
/// menus name the app they belong to, and what Hey AI is doing right now.
struct MenuHeader: View {
    enum Tone { case on, off, problem }

    let status: String
    let tone: Tone
    /// The last thing Hey AI did, if anything.
    let detail: String?
    /// Set to the menu's width so long messages wrap instead of widening the menu.
    var width: CGFloat = 280

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .padding(.top, -1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline) {
                    BrandWordmark().fill(Color.primary).frame(width: 13 * Brand.wordmarkAspect, height: 13)
                    Spacer(minLength: 12)
                    Text(version).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    dot.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.5 }
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder private var dot: some View {
        switch tone {
        case .on: Circle().fill(Color(nsColor: Brand.nsSignal)).frame(width: 6, height: 6)
        case .off: Circle().strokeBorder(Color.secondary, lineWidth: 1).frame(width: 6, height: 6)
        case .problem: Circle().fill(Color.orange).frame(width: 6, height: 6)
        }
    }
}

extension MenuHeader {
    /// A menu item that shows the header. It's informational only, so it never highlights.
    func menuItem(width: CGFloat) -> NSMenuItem {
        var header = self
        header.width = max(width, 260)
        let host = NSHostingView(rootView: header)
        let fitting = host.fittingSize
        // Measured once; after that the menu sets the width and SwiftUI shouldn't fight it.
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: header.width, height: fitting.height)
        host.autoresizingMask = [.width]
        let item = NSMenuItem()
        item.view = host
        item.isEnabled = false
        return item
    }
}
