import AppKit
import OSLog
import ServiceManagement
import ThinkMyDayCore

/// Menu-bar shell: 开启一天 / 结束一天, record status, permissions and login item.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private(set) var store: RecordStore?
    private var storeError: String?
    private var chromeState: PermissionState = .unknown("检查中…")
    private let panels = PanelPresenter()
    private var openDay: ReviewDay?
    private var lastDay: ReviewDay?
    private var statusTimer: Timer?

    private let log = Logger(subsystem: "com.jonascyang.thinkmyday", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try RecordStore(url: RecordStore.defaultURL())
        } catch {
            storeError = "\(error)"
            log.error("store failed to open: \(error, privacy: .public)")
        }
        log.notice("launched; accessibility \(Permissions.accessibility().label, privacy: .public), screen recording \(Permissions.screenRecording().label, privacy: .public)")

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        if Permissions.accessibility() != .granted { Permissions.requestAccessibility() }
        // Requesting once is what adds the app to the Screen Recording list in System Settings.
        if Permissions.screenRecording() != .granted { Permissions.requestScreenRecording() }
        refreshChrome(ask: false)

        Task { await reloadDays() }
        // The ✓ of an ended day turns back into ○ when the calendar day changes.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in self.updateIcon() }
        }
        if Settings.plannedStart == nil { showPlannedStart() }
    }

    // MARK: - 复盘日

    private var status: DayStatus {
        DayStatus.current(open: openDay, last: lastDay, plan: Settings.plannedStart, now: Date())
    }

    private func reloadDays() async {
        guard let store else { return updateIcon() }
        do {
            openDay = try await store.openDay()
            lastDay = try await store.days().last
        } catch {
            log.error("reading days failed: \(error, privacy: .public)")
        }
        updateIcon()
    }

    private func updateIcon() {
        let (symbol, label) = switch status {
        case .notStarted: ("circle", "未开启")
        case .recording: ("circle.fill", "记录中")
        case .ended: ("checkmark.circle", "已结束")
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Think My Day：\(label)")
    }

    private func statusLine() -> String {
        let plan = Settings.plannedStart
        switch status {
        case .recording(let day):
            let since = day.startedAt.formatted(date: .omitted, time: .shortened)
            let comparison = day.plannedStart.map { "（\(PlanComparison.text(start: day.startedAt, planned: $0))）" } ?? ""
            return "记录中 · \(since) 开启\(comparison)"
        case .ended(let day):
            let range = [day.startedAt, day.endedAt ?? Date()].map { $0.formatted(date: .omitted, time: .shortened) }
            return "今天已结束（\(range[0])–\(range[1])）"
        case .notStarted(let late?):
            return "未开启 · 比计划晚了 \(PlanComparison.duration(late))"
        case .notStarted(nil):
            return plan.map { "未开启 · 计划 \($0.clockText) 开始" } ?? "未开启"
        }
    }

    @objc private func showStartDay() {
        guard let store else { return }
        let plan = Settings.plannedStart
        let unfinished = openDay
        panels.show(title: "开启一天") { close in
            StartDayView(plannedStart: plan, unfinished: unfinished, start: { [weak self] in
                let (day, ended) = try await store.startDay(at: Date(), plannedStart: plan)
                if let ended { self?.log.notice("day \(ended.id, privacy: .public) closed by the next 开启一天") }
                await self?.reloadDays()
                return day
            }, close: close)
        }
    }

    @objc private func endDay() {
        guard let store else { return }
        Task {
            do { try await store.endDay(at: Date()) } catch { log.error("ending day failed: \(error, privacy: .public)") }
            await reloadDays()
        }
    }

    @objc private func showPlannedStart() {
        panels.show(title: "计划开始时刻") { close in
            PlannedStartView(current: Settings.plannedStart, save: { [weak self] plan in
                Settings.plannedStart = plan
                self?.updateIcon()
            }, close: close)
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "dev"))"
        menu.addItem(disabled("Think My Day \(version)"))
        if let storeError { menu.addItem(disabled("记录库打不开：\(storeError)")) }

        menu.addItem(.separator())
        menu.addItem(disabled(statusLine()))
        let dayItem = if case .recording = status {
            NSMenuItem(title: "结束一天", action: #selector(endDay), keyEquivalent: "")
        } else {
            NSMenuItem(title: "开启一天…", action: #selector(showStartDay), keyEquivalent: "")
        }
        dayItem.target = self
        dayItem.isEnabled = store != nil
        menu.addItem(dayItem)
        let planItem = NSMenuItem(title: "计划开始时刻：\(Settings.plannedStart?.clockText ?? "未设置")…",
                                  action: #selector(showPlannedStart), keyEquivalent: "")
        planItem.target = self
        menu.addItem(planItem)

        menu.addItem(.separator())
        menu.addItem(disabled("系统授权"))
        for permission in Permission.allCases {
            let state = state(of: permission)
            let suffix = state == .granted ? "" : (permission.required ? "（必须）" : "")
            let item = NSMenuItem(title: "\(permission.title)：\(state.label)\(suffix)", action: #selector(fixPermission(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = permission
            item.image = NSImage(systemSymbolName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle",
                                 accessibilityDescription: state.label)
            item.isEnabled = state != .granted
            menu.addItem(item)
        }
        refreshChrome(ask: false)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "开机自动启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let folder = NSMenuItem(title: "打开数据文件夹", action: #selector(openDataFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Think My Day", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func state(of permission: Permission) -> PermissionState {
        switch permission {
        case .accessibility: Permissions.accessibility()
        case .screenRecording: Permissions.screenRecording()
        case .chromeAutomation: chromeState
        }
    }

    // MARK: - Actions

    @objc private func fixPermission(_ sender: NSMenuItem) {
        guard let permission = sender.representedObject as? Permission else { return }
        switch permission {
        case .accessibility:
            Permissions.requestAccessibility()
            NSWorkspace.shared.open(permission.settingsURL)
        case .screenRecording:
            // The prompt appears only the first time; after that the user has to change it in System Settings.
            Permissions.requestScreenRecording()
            NSWorkspace.shared.open(permission.settingsURL)
        case .chromeAutomation:
            if chromeState == .denied {
                NSWorkspace.shared.open(permission.settingsURL)
            } else {
                refreshChrome(ask: true)
            }
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机自动启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func openDataFolder() {
        let dir = RecordStore.defaultURL().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func refreshChrome(ask: Bool) {
        Task {
            let state = await Task.detached { Permissions.chromeAutomation(ask: ask) }.value
            self.chromeState = state
        }
    }
}
