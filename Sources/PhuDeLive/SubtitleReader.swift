import AppKit
import ScreenCaptureKit
import Vision

/// Chụp vùng phụ đề ~4 lần/giây, đọc chữ tiếng Anh bằng Vision (chạy trên Neural Engine).
@MainActor
final class SubtitleReader {
    var onText: ((String, CGRect) -> Void)?   // chữ + khung chữ (toạ độ màn hình); "" khi không có chữ
    var onError: ((String) -> Void)?

    private var timer: Timer?
    private var busy = false
    private var filter: SCContentFilter?
    private var filterScreen: CGDirectDisplayID = 0
    private var filterTime = Date.distantPast
    private var emptyCount = 0
    private var lastKey = ""

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func reset() { filter = nil; lastKey = ""; emptyCount = 0 }

    private func screen(for r: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(r) } ?? NSScreen.main
    }

    private func displayID(_ s: NSScreen) -> CGDirectDisplayID {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    private func makeFilter(_ s: NSScreen) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = displayID(s)
        guard let disp = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else {
            throw NSError(domain: "PhuDeLive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy màn hình"])
        }
        // loại chính app này ra khỏi ảnh chụp để không tự đọc lại chữ tiếng Việt của mình
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        filter = SCContentFilter(display: disp, excludingApplications: me, exceptingWindows: [])
        filterScreen = id
        filterTime = Date()
    }

    private func tick() {
        let st = AppState.shared
        guard !busy, st.enabled, !st.picking else { return }
        let region = st.region
        guard region.width > 20, region.height > 10, let scr = screen(for: region) else { return }
        busy = true
        Task { @MainActor in
            defer { self.busy = false }
            do {
                if self.filter == nil || self.filterScreen != self.displayID(scr) || Date().timeIntervalSince(self.filterTime) > 5 {
                    try await self.makeFilter(scr)
                }
                guard let filter = self.filter else { return }
                let cfg = SCStreamConfiguration()
                cfg.sourceRect = CGRect(x: region.minX - scr.frame.minX,
                                        y: scr.frame.maxY - region.maxY,
                                        width: region.width, height: region.height)
                let scale = scr.backingScaleFactor
                cfg.width = Int(region.width * scale)
                cfg.height = Int(region.height * scale)
                cfg.showsCursor = false
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                let (text, nbox) = await Task.detached(priority: .userInitiated) { Self.ocr(img) }.value
                self.deliver(text, nbox, region)
            } catch {
                self.filter = nil
                self.onError?(error.localizedDescription)
            }
        }
    }

    private func deliver(_ text: String, _ nbox: CGRect, _ region: CGRect) {
        let clean = Self.cleanup(text)
        if clean.isEmpty {
            emptyCount += 1
            if emptyCount >= 2, !lastKey.isEmpty { lastKey = ""; onText?("", .zero) }
            return
        }
        emptyCount = 0
        let key = clean.lowercased().filter { $0.isLetter || $0.isNumber }
        if key == lastKey { return }
        lastKey = key
        let box = CGRect(x: region.minX + nbox.minX * region.width,
                         y: region.minY + nbox.minY * region.height,
                         width: nbox.width * region.width,
                         height: nbox.height * region.height)
        onText?(clean, box)
    }

    /// Bỏ các dòng không phải phụ đề (giờ phát, số trang…)
    nonisolated static func cleanup(_ t: String) -> String {
        t.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { line in
                let letters = line.filter { $0.isLetter }.count
                return letters >= 2
            }
            .joined(separator: "\n")
    }

    nonisolated static func ocr(_ img: CGImage) -> (String, CGRect) {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["en-US"]
        req.usesLanguageCorrection = true
        req.minimumTextHeight = 0.06
        do { try VNImageRequestHandler(cgImage: img, options: [:]).perform([req]) } catch { return ("", .zero) }
        var lines: [(String, CGRect)] = []
        for o in req.results ?? [] {
            if let c = o.topCandidates(1).first, c.confidence >= 0.35 { lines.append((c.string, o.boundingBox)) }
        }
        lines.sort { $0.1.midY > $1.1.midY } // dòng trên trước
        let text = lines.map { $0.0 }.joined(separator: "\n")
        let box = lines.reduce(CGRect.null) { $0.union($1.1) }
        return (text, box.isNull ? .zero : box)
    }
}
