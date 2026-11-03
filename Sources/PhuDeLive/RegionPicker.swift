import AppKit

/// Màn hình mờ để người dùng kéo chuột khoanh vùng phụ đề.
final class RegionPicker: NSWindow {
    var done: ((CGRect?) -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.35)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        let v = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.owner = self
        contentView = v
    }

    override var canBecomeKey: Bool { true }

    func finish(_ r: CGRect?) {
        orderOut(nil)
        done?(r)
        done = nil
    }
}

final class PickerView: NSView {
    weak var owner: RegionPicker?
    private var start: NSPoint?
    private var cur: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    private var rect: NSRect? {
        guard let a = start, let b = cur else { return nil }
        return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func mouseDown(with e: NSEvent) { start = convert(e.locationInWindow, from: nil); cur = start; needsDisplay = true }
    override func mouseDragged(with e: NSEvent) { cur = convert(e.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        cur = convert(e.locationInWindow, from: nil)
        guard let r = rect, r.width > 30, r.height > 15, let w = owner else { start = nil; needsDisplay = true; return }
        w.finish(w.convertToScreen(r))
    }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { owner?.finish(nil) } }

    override func draw(_ dirtyRect: NSRect) {
        let msg = "Kéo chuột khoanh vùng có phụ đề tiếng Anh (khoanh rộng hơn dòng chữ một chút, đủ chỗ cho 2 dòng).\nBấm Esc để huỷ."
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white, .paragraphStyle: para
        ]
        let s = NSAttributedString(string: msg, attributes: attr)
        let h: CGFloat = 80
        let r = NSRect(x: 40, y: bounds.midY + 60, width: bounds.width - 80, height: h)
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: -10, dy: -10), xRadius: 12, yRadius: 12).fill()
        s.draw(in: r)
        if let sel = rect {
            NSColor(white: 1, alpha: 0.12).setFill(); sel.fill()
            NSColor.systemRed.setStroke()
            let p = NSBezierPath(rect: sel); p.lineWidth = 3; p.stroke()
        }
    }
}
