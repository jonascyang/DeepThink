import AppKit
import ApplicationServices
import ThinkMyDayCore

/// Wakes the capturer: on app switches, focus and title changes, typing (debounced), every 5 s while nothing happens,
/// and on sleep, wake, lock and unlock.
@MainActor
final class CaptureTriggers {
    static let interval: TimeInterval = 5
    static let debounce: TimeInterval = 1

    private let capturer: Capturer
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var observer: AXObserver?
    private var observedPid: pid_t?
    private var tokens: [NSObjectProtocol] = []

    init(capturer: Capturer) { self.capturer = capturer }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capturer.trigger() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        tokens = [
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.observeFrontmostApp()
                    self?.schedule(after: 0.5) // let the new app raise its window
                }
            },
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.capturer.presence(.asleep) }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.capturer.presence(.awake) }
            },
            // The display can sleep while the Mac stays awake; accessibility then sees no windows at all (M0b).
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.capturer.presence(.asleep) }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.capturer.presence(.awake) }
            },
            DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.capturer.presence(.locked) }
            },
            DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.capturer.presence(.unlocked) }
            },
        ]
        observeFrontmostApp()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pending?.cancel()
        tokens.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
        tokens = []
        removeObserver()
    }

    private func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.capturer.trigger() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Accessibility notifications of the frontmost app

    private static let notifications = [
        kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXTitleChangedNotification,
        kAXFocusedUIElementChangedNotification, kAXValueChangedNotification,
    ]

    private func observeFrontmostApp() {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != observedPid else { return }
        removeObserver()
        guard AXIsProcessTrusted() else { return }
        let pid = front.processIdentifier
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let triggers = Unmanaged<CaptureTriggers>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { triggers.schedule(after: CaptureTriggers.debounce) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications { AXObserverAddNotification(created, app, name as CFString, context) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPid = pid
    }

    private func removeObserver() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        observedPid = nil
    }
}
