import AppKit
import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState.shared
    let reader = SubtitleReader()
    let translator = SubTranslator()
    var overlay: OverlayWindow!
    var settingsWin: NSWindow!
    var statusItem: NSStatusItem!
    var toggleItem: NSMenuItem!
    var hotKey: HotKey?
    var picker: RegionPicker?

    var currentEN = ""
    var currentBox = CGRect.zero
    var inflight = false

    func applicationDidFinishLaunching(_ n: Notification) {
        if state.region.width < 20 { state.region = AppState.defaultRegion() }

        overlay = OverlayWindow()
        overlay.setFrame(state.region, display: false)
        overlay.orderFrontRegardless()

        buildSettings()
        buildMainMenu()
        buildStatusItem()

        reader.onText = { [weak self] t, b in self?.handle(t, b) }
        reader.onError = { [weak self] e in
            self?.state.status = "Không chụp được màn hình (\(e)). Vào Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Ghi màn hình, bật Phụ đề Việt Live rồi mở lại app."
        }
        state.onChange = { [weak self] in self?.settingsChanged() }
        state.onEngineChange = { [weak self] in self?.translator.resetSession(); self?.retranslate() }
        reader.start()

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey)) {
            Task { @MainActor in AppState.shared.enabled.toggle() }
        }
        settingsWin.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }

    // MARK: phụ đề
    func handle(_ text: String, _ box: CGRect) {
        guard state.enabled else { return }
        if text.isEmpty {
            currentEN = ""
            overlay.clear()
            return
        }
        currentEN = text
        currentBox = box
        state.lastEN = text.replacingOccurrences(of: "\n", with: " ")
        let vi = translator.cached(text)
        if let vi { state.lastVI = vi }
        overlay.show(en: text, vi: vi, box: box)
        pump()
    }

    func pump() {
        guard !inflight, !currentEN.isEmpty, translator.cached(currentEN) == nil else { return }
        let want = currentEN
        inflight = true
        Task { @MainActor in
            let vi = await translator.translate(want)
            inflight = false
            if currentEN == want {
                if let vi { state.lastVI = vi }
                overlay.show(en: want, vi: vi, box: currentBox)
            } else {
                pump()
            }
        }
    }

    func retranslate() {
        guard !currentEN.isEmpty else { return }
        overlay.show(en: currentEN, vi: translator.cached(currentEN), box: currentBox)
        pump()
    }

    func settingsChanged() {
        toggleItem?.state = state.enabled ? .on : .off
        if !state.enabled {
            currentEN = ""
            overlay.clear()
            reader.reset()
        } else if !currentEN.isEmpty {
            overlay.show(en: currentEN, vi: translator.cached(currentEN), box: currentBox)
        }
    }

    // MARK: khoanh vùng
    @objc func pickRegion() {
        let mouse = NSEvent.mouseLocation
        let scr = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        state.picking = true
        overlay.clear()
        settingsWin.orderOut(nil)
        let p = RegionPicker(screen: scr)
        p.done = { [weak self] r in
            guard let self else { return }
            self.state.picking = false
            if let r { self.state.region = r; self.reader.reset(); self.currentEN = "" }
            self.picker = nil
            self.showSettings()
        }
        picker = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(p.contentView)
    }

    // MARK: cửa sổ, menu
    func buildSettings() {
        let host = NSHostingController(rootView: SettingsView(pickRegion: { [weak self] in self?.pickRegion() }))
        settingsWin = NSWindow(contentViewController: host)
        settingsWin.title = "Phụ đề Việt Live"
        settingsWin.styleMask = [.titled, .closable, .miniaturizable]
        settingsWin.isReleasedWhenClosed = false
        settingsWin.center()
    }

    @objc func showSettings() {
        settingsWin.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleEnabled() { state.enabled.toggle() }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "VI"
        statusItem.button?.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        let m = NSMenu()
        toggleItem = NSMenuItem(title: "Dịch phụ đề (⌃⌥V)", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.state = state.enabled ? .on : .off
        m.addItem(toggleItem)
        m.addItem(NSMenuItem(title: "Khoanh vùng phụ đề…", action: #selector(pickRegion), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "Mở bảng điều khiển", action: #selector(showSettings), keyEquivalent: ""))
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Thoát", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for i in m.items where i.action != #selector(NSApplication.terminate(_:)) { i.target = self }
        statusItem.menu = m
    }

    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Ẩn Phụ đề Việt Live", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Thoát Phụ đề Việt Live", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: "Cửa sổ")
        winMenu.addItem(NSMenuItem(title: "Đóng", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        winItem.submenu = winMenu
        NSApp.mainMenu = main
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
