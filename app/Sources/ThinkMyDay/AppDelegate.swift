import AppKit
import OSLog
import ServiceManagement
import ThinkMyDayCore

/// Menu-bar shell. 开启一天 and the record status arrive with #5; this holds the store, permissions and login item.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private(set) var store: RecordStore?
    private var storeError: String?
    private var chromeState: PermissionState = .unknown("检查中…")

    private let log = Logger(subsystem: "com.jonascyang.thinkmyday", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try RecordStore(url: RecordStore.defaultURL())
        } catch {
            storeError = "\(error)"
            log.error("store failed to open: \(error, privacy: .public)")
        }
        log.notice("launched; accessibility \(Permissions.accessibility().label, privacy: .public), screen recording \(Permissions.screenRecording().label, privacy: .public)")

        statusItem.button?.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Think My Day：未开启")
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        if Permissions.accessibility() != .granted { Permissions.requestAccessibility() }
        // Requesting once is what adds the app to the Screen Recording list in System Settings.
        if Permissions.screenRecording() != .granted { Permissions.requestScreenRecording() }
        refreshChrome(ask: false)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "dev"))"
        menu.addItem(disabled("Think My Day \(version)"))
        if let storeError { menu.addItem(disabled("记录库打不开：\(storeError)")) }

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
