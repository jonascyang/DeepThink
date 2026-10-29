import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sampler = Sampler()
    private let resources = ResourceProbe()
    private var statusItem: NSStatusItem!
    private var timers: [Timer] = []
    private var paused = false
    private var startedAt = Date()

    static let sampleInterval: TimeInterval = 5

    /// Development switches: M0B_SMOKE_SECONDS=N writes a report and quits after N seconds
    /// without asking for any permission and without touching Chrome; M0B_DATA_DIR redirects the records.
    private let smokeSeconds = ProcessInfo.processInfo.environment["M0B_SMOKE_SECONDS"].flatMap(Double.init)

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchProbe.run()
        if let smokeSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + smokeSeconds) { [weak self] in
                print(Report.generate().path)
                self?.timers.forEach { $0.invalidate() }
                NSApp.terminate(nil)
            }
        } else {
            // Ask for permissions; macOS shows its own prompts and the user decides.
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        }

        sampler.ocr = OCRProbe()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "M0b"
        rebuildMenu()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        timers = [
            Timer.scheduledTimer(withTimeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
                guard let self, !self.paused else { return }
                self.sampler.trigger("timer")
            },
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.resources.tick() },
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                guard let self, !self.paused, self.smokeSeconds == nil else { return }
                ChromeProbe.run()
            },
            Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.rebuildMenu() },
        ]
        resources.tick()
        DispatchQueue.global(qos: .utility).async { HistoryProbe.run() }
    }

    @objc private func appActivated() {
        guard !paused else { return }
        // Give the new app a moment to raise its window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.sampler.trigger("activate") }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let minutes = Int(Date().timeIntervalSince(startedAt) / 60)
        menu.addItem(withTitle: "本次运行 \(minutes) 分钟，采样 \(sampler.sampleCount) 次", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "辅助功能：\(AXIsProcessTrusted() ? "已授权" : "未授权（点此打开设置）")",
                     action: AXIsProcessTrusted() ? nil : #selector(openAXSettings), keyEquivalent: "")
        menu.addItem(withTitle: "屏幕录制：\(CGPreflightScreenCaptureAccess() ? "已授权" : "未授权（点此打开设置）")",
                     action: CGPreflightScreenCaptureAccess() ? nil : #selector(openScreenSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: paused ? "继续采样" : "暂停采样", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "生成报告", action: #selector(makeReport), keyEquivalent: "r")
        menu.addItem(withTitle: "打开数据文件夹", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(withTitle: "清空已收集的数据", action: #selector(clearData), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "生成报告并退出", action: #selector(reportAndQuit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
        statusItem.button?.title = paused ? "M0b ⏸" : (AXIsProcessTrusted() ? "M0b" : "M0b ⚠︎")
    }

    @objc private func togglePause() { paused.toggle(); rebuildMenu() }

    @objc private func makeReport() {
        HistoryProbe.run()
        NSWorkspace.shared.activateFileViewerSelecting([Report.generate()])
    }

    @objc private func openFolder() { NSWorkspace.shared.open(RecordStore.shared.dir) }

    @objc private func clearData() {
        let alert = NSAlert()
        alert.messageText = "清空已收集的统计数据？"
        alert.informativeText = "会删除 records.jsonl 里的全部记录（包括历次启动的授权记录），已生成的报告不受影响。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            RecordStore.shared.clear()
            LaunchProbe.run()
        }
    }

    @objc private func reportAndQuit() {
        makeReport()
        NSApp.terminate(nil)
    }

    @objc private func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openScreenSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
