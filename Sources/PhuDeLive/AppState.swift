import AppKit

enum DisplayMode: String, CaseIterable, Hashable { case vi, both }
enum Engine: String, CaseIterable, Hashable { case apple, google }

/// Toàn bộ cài đặt + trạng thái hiển thị, lưu vào UserDefaults.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled"); onChange?() } }
    @Published var mode: DisplayMode { didSet { d.set(mode.rawValue, forKey: "mode"); onChange?() } }
    @Published var engine: Engine { didSet { d.set(engine.rawValue, forKey: "engine"); onEngineChange?() } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize"); onChange?() } }
    @Published var region: CGRect { didSet { d.set(NSStringFromRect(region), forKey: "region") } }

    @Published var lastEN = ""
    @Published var lastVI = ""
    @Published var status = "Đang chờ phụ đề…"
    var picking = false

    var onChange: (() -> Void)?
    var onEngineChange: (() -> Void)?

    private init() {
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        mode = DisplayMode(rawValue: d.string(forKey: "mode") ?? "") ?? .vi
        engine = Engine(rawValue: d.string(forKey: "engine") ?? "") ?? .apple
        fontSize = d.object(forKey: "fontSize") as? Double ?? 30
        if let s = d.string(forKey: "region") { region = NSRectFromString(s) } else { region = .zero }
    }

    static func defaultRegion() -> CGRect {
        let f = (NSScreen.main ?? NSScreen.screens[0]).frame
        return CGRect(x: f.minX + f.width * 0.1, y: f.minY + f.height * 0.03,
                      width: f.width * 0.8, height: f.height * 0.22)
    }
}
