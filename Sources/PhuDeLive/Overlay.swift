import AppKit

/// Cửa sổ trong suốt luôn nổi trên cùng (kể cả khi Stremio toàn màn hình), không nhận chuột.
final class OverlayWindow: NSPanel {
    let sub = SubView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .none
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = sub
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @MainActor
    func show(en: String, vi: String?, box: CGRect) {
        let st = AppState.shared
        let region = st.region
        var frame = NSRect(x: region.minX, y: region.minY, width: region.width, height: region.height + 260)
        if let scr = NSScreen.screens.first(where: { $0.frame.intersects(region) }) {
            frame = frame.intersection(scr.frame)
        }
        if self.frame != frame { setFrame(frame, display: false) }
        sub.en = en
        sub.vi = vi ?? ""
        sub.mode = st.mode
        sub.fontSize = CGFloat(st.fontSize)
        sub.box = box.offsetBy(dx: -frame.minX, dy: -frame.minY)
        sub.needsDisplay = true
        orderFrontRegardless()
    }

    @MainActor
    func clear() {
        sub.en = ""; sub.vi = ""
        sub.needsDisplay = true
    }
}

final class SubView: NSView {
    var en = ""
    var vi = ""
    var mode: DisplayMode = .vi
    var fontSize: CGFloat = 30
    var box: CGRect = .zero

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard !en.isEmpty else { return }

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let viAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white, .paragraphStyle: para
        ]
        let enAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize * 0.72, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 1, green: 0.88, blue: 0.4, alpha: 1), .paragraphStyle: para
        ]
        let waitAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize * 0.85, weight: .regular),
            .foregroundColor: NSColor(white: 1, alpha: 0.6), .paragraphStyle: para
        ]

        let s = NSMutableAttributedString()
        let enFlat = en.replacingOccurrences(of: "\n", with: " ")
        if mode == .both { s.append(NSAttributedString(string: enFlat, attributes: enAttr)) }
        if !vi.isEmpty {
            if s.length > 0 { s.append(NSAttributedString(string: "\n", attributes: viAttr)) }
            s.append(NSAttributedString(string: vi, attributes: viAttr))
        } else if mode == .vi {
            s.append(NSAttributedString(string: enFlat, attributes: waitAttr))
        }

        let maxW = bounds.width * 0.98
        let pad: CGFloat = 14
        let size = s.boundingRect(with: NSSize(width: maxW - pad * 2, height: 10_000),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let b = box.isEmpty ? CGRect(x: bounds.midX - 100, y: 20, width: 200, height: fontSize) : box
        let w = min(maxW, max(b.width + 20, ceil(size.width) + pad * 2))
        let h = max(b.height + 12, ceil(size.height) + 12)
        var bg = NSRect(x: b.midX - w / 2, y: b.minY - 6, width: w, height: h)
        bg.origin.x = max(bounds.minX + 2, min(bg.origin.x, bounds.maxX - w - 2))
        bg.origin.y = max(bounds.minY, min(bg.origin.y, bounds.maxY - h))

        NSColor(white: 0, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 8, yRadius: 8).fill()
        let tr = NSRect(x: bg.minX + pad, y: bg.minY + (h - size.height) / 2, width: w - pad * 2, height: ceil(size.height))
        s.draw(with: tr, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
