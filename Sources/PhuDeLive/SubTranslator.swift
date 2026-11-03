import Foundation
import Translation

/// Dịch Anh → Việt: Apple Translation (offline) hoặc Google Dịch (online).
@MainActor
final class SubTranslator {
    private var cache: [String: String] = [:]
    private var appleSession: AnyObject?

    func cached(_ text: String) -> String? { cache[key(text)] }
    func resetSession() { appleSession = nil }

    private func key(_ t: String) -> String {
        AppState.shared.engine.rawValue + "|" + t.replacingOccurrences(of: "\n", with: " ")
    }

    func translate(_ text: String) async -> String? {
        let k = key(text)
        if let c = cache[k] { return c }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        var out: String?
        if AppState.shared.engine == .apple { out = await apple(flat) }
        if out == nil { out = await google(flat) }
        if let o = out, !o.isEmpty { cache[k] = o; if cache.count > 5000 { cache.removeAll() } }
        return out
    }

    private func apple(_ s: String) async -> String? {
        if #available(macOS 26.0, *) {
            do {
                if appleSession == nil {
                    appleSession = TranslationSession(installedSource: Locale.Language(identifier: "en"),
                                                      target: Locale.Language(identifier: "vi"))
                }
                if let sess = appleSession as? TranslationSession {
                    let r = try await sess.translate(s)
                    return r.targetText
                }
            } catch {
                appleSession = nil
                AppState.shared.status = "Chưa có gói dịch offline Anh – Việt nên đang dùng Google. Bấm “Tải gói dịch offline”."
            }
        } else {
            AppState.shared.status = "Dịch offline cần macOS 26, đang dùng Google."
        }
        return nil
    }

    private func google(_ s: String) async -> String? {
        var c = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        c.queryItems = [
            .init(name: "client", value: "gtx"), .init(name: "sl", value: "en"),
            .init(name: "tl", value: "vi"), .init(name: "dt", value: "t"), .init(name: "q", value: s)
        ]
        guard let url = c.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let segs = json.first as? [Any] else { return nil }
            let t = segs.compactMap { ($0 as? [Any])?.first as? String }.joined()
            return t.isEmpty ? nil : t
        } catch {
            AppState.shared.status = "Không dịch được (mạng?): \(error.localizedDescription)"
            return nil
        }
    }
}
