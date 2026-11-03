import SwiftUI
import Translation

struct SettingsView: View {
    @ObservedObject var state = AppState.shared
    var pickRegion: () -> Void
    @State private var cfg: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Phụ đề Việt Live").font(.title2.bold())
                Spacer()
                Toggle("Dịch phụ đề", isOn: $state.enabled).toggleStyle(.switch)
            }
            Text("Phím tắt bật/tắt: ⌃ Control + ⌥ Option + V").font(.callout).foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Khoanh vùng phụ đề…", action: pickRegion)
                        Text(String(format: "%.0f × %.0f điểm", state.region.width, state.region.height))
                            .foregroundStyle(.secondary)
                    }
                    Picker("Hiển thị", selection: $state.mode) {
                        Text("Chỉ tiếng Việt").tag(DisplayMode.vi)
                        Text("Song ngữ Anh – Việt").tag(DisplayMode.both)
                    }
                    Picker("Bộ dịch", selection: $state.engine) {
                        Text("Apple – offline, chạy trên máy").tag(Engine.apple)
                        Text("Google – online, cần mạng").tag(Engine.google)
                    }
                    HStack {
                        Text("Cỡ chữ")
                        Slider(value: $state.fontSize, in: 16...64, step: 1)
                        Text("\(Int(state.fontSize))").frame(width: 28)
                    }
                    Button("Tải gói dịch offline Anh – Việt") {
                        if cfg == nil {
                            cfg = TranslationSession.Configuration(source: Locale.Language(identifier: "en"),
                                                                   target: Locale.Language(identifier: "vi"))
                        } else {
                            cfg?.invalidate()
                        }
                    }
                }.padding(6)
            }

            GroupBox("Đang đọc được") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.lastEN.isEmpty ? "—" : state.lastEN).foregroundStyle(.orange)
                    Text(state.lastVI.isEmpty ? "—" : state.lastVI).font(.headline)
                    Text(state.status).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            Text("""
            Cách dùng: mở phim trong Stremio, bật phụ đề tiếng Anh, bấm “Khoanh vùng phụ đề…” rồi kéo chuột quanh chỗ phụ đề hiện. \
            Chữ tiếng Việt sẽ đè kín lên dòng tiếng Anh. Lần đầu macOS sẽ hỏi quyền Ghi màn hình: hãy cho phép rồi mở lại app.
            """)
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 480)
        .translationTask(cfg) { session in
            do {
                try await session.prepareTranslation()
                await MainActor.run { AppState.shared.status = "Gói dịch offline Anh – Việt đã sẵn sàng." }
            } catch {
                await MainActor.run { AppState.shared.status = "Chưa tải được gói dịch: \(error.localizedDescription)" }
            }
        }
    }
}
