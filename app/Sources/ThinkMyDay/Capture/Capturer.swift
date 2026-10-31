import AppKit
import ApplicationServices
import OSLog
import ThinkMyDayCore

/// Reads the visible windows into 记录 while a 复盘日 is open.
/// All mutable state lives on `queue`; accessibility calls block, so they never run on the main thread.
final class Capturer: @unchecked Sendable {
    struct Options: Sendable {
        var ocrEnabled = true
        var idleThreshold: TimeInterval = 180
        var blockList = BlockList.presets
    }

    private let queue = DispatchQueue(label: "thinkmyday.capture", qos: .utility)
    private let log = Logger(subsystem: "com.jonascyang.thinkmyday", category: "capture")
    private let writes: AsyncStream<Record>.Continuation
    private let store: RecordStore

    // Queue-confined state.
    private var dayID: UUID?
    private var options = Options()
    private var history = LineHistory()
    private var ocrBudget = OCRBudget()
    private var ocrPending: Set<CGWindowID> = []
    private var unreadable: Set<CGWindowID> = []
    /// Windows currently left unread, so the placeholder is written once per stretch, not every sample.
    private var hidden: [CGWindowID: Gap.Reason] = [:]
    private var unmatched: Set<CGWindowID> = []
    private var layouts = LayoutTracker()
    private var flagged: Set<pid_t> = []
    private var lastFocus: Focus?
    private var trusted: Bool?
    private var idle = IdleTracker()
    private var paused = false
    private var busy = false
    private var lastCompare = Date.distantPast
    /// Development: TMD_OCR_COMPARE=1 logs OCR next to the accessibility count for the focused window once a minute.
    private static let compareOCR = ProcessInfo.processInfo.environment["TMD_OCR_COMPARE"] != nil

    /// Below this many visible characters a window counts as unreadable by accessibility and goes to OCR.
    static let ocrThreshold = 50

    init(store: RecordStore) {
        self.store = store
        let (stream, continuation) = AsyncStream.makeStream(of: Record.self)
        writes = continuation
        let log = self.log
        // One writer task keeps records in the order they were captured.
        Task.detached(priority: .utility) {
            for await record in stream {
                do { try await store.append(.recordCaptured(record)) } catch { log.error("record dropped: \(error, privacy: .public)") }
            }
        }
    }

    // MARK: - Control

    func start(dayID: UUID, options: Options) {
        queue.async {
            self.dayID = dayID
            self.options = options
            self.idle = IdleTracker(threshold: options.idleThreshold)
            self.history.reset()
            self.lastFocus = nil
            self.unreadable = []
            self.hidden = [:]
            self.unmatched = []
            self.layouts.reset()
            self.trusted = nil
            self.write(.presence, Presence(state: .recordingStarted, since: Date()))
        }
        trigger()
    }

    /// At quit: writes 停止记录 straight to the store and waits for it, so the timeline can tell a normal quit
    /// from a crash. (Ending the day needs no such record; the day's end time says it.)
    func finish() async {
        let dayID: UUID? = queue.sync {
            let id = self.dayID
            self.dayID = nil
            return id
        }
        guard let dayID, let record = try? Record(dayID: dayID, at: Date(), kind: .presence,
                                                  body: Presence(state: .recordingStopped, since: Date())) else { return }
        do { try await store.append(.recordCaptured(record)) } catch { log.error("stop record failed: \(error, privacy: .public)") }
    }

    func stop() { queue.async { self.dayID = nil; self.history.reset() } }

    func update(options: Options) {
        queue.async {
            self.options = options
            self.idle.threshold = options.idleThreshold
        }
    }

    /// Sleep and lock stop all reading; the edges themselves are recorded.
    func presence(_ state: Presence.State) {
        queue.async {
            switch state {
            case .asleep, .locked: self.paused = true
            case .awake, .unlocked: self.paused = false
            case .idle, .active, .recordingStarted, .recordingStopped: break
            }
            self.write(.presence, Presence(state: state, since: Date()))
        }
        if state == .unlocked || state == .awake { trigger() }
    }

    /// Takes a sample now unless one is running.
    func trigger() {
        let tabsNeeded = Windows.visible().contains { NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier == Permissions.chromeBundleID }
        // AppleScript runs on the main thread; fetch Chrome's tabs here and hand them to the queue.
        let tabs: [Chrome.Tab] = if tabsNeeded {
            Thread.isMainThread ? MainActor.assumeIsolated { Chrome.activeTabs() } : DispatchQueue.main.sync { MainActor.assumeIsolated { Chrome.activeTabs() } }
        } else { [] }
        queue.async {
            guard !self.busy else { return }
            self.busy = true
            defer { self.busy = false }
            self.sample(chromeTabs: tabs)
        }
    }

    // MARK: - Sampling (on queue)

    private func sample(chromeTabs: [Chrome.Tab]) {
        guard dayID != nil, !paused else { return }
        let now = Date()

        if let change = idle.update(secondsSinceInput: Self.secondsSinceInput(), now: now) { write(.presence, change) }

        let isTrusted = AXIsProcessTrusted()
        if isTrusted != trusted {
            trusted = isTrusted
            if !isTrusted { write(.gap, Gap(reason: .noAccessibilityPermission)) }
        }
        guard isTrusted else { return }

        let windows = Windows.visible().filter { $0.visibleFraction >= 0.05 }
        func tab(_ bundleID: String, _ bounds: CGRect?) -> Chrome.Tab? {
            guard bundleID == Permissions.chromeBundleID, let bounds else { return nil }
            return Chrome.tab(for: bounds, in: chromeTabs)
        }
        func decide(_ bundleID: String, _ tab: Chrome.Tab?) -> ReadDecision {
            PrivacyRules.decide(bundleID: bundleID, browserURL: tab?.url, incognito: tab?.incognito ?? false, blockList: options.blockList)
        }

        let focused = Windows.focused()
        if let focused {
            let bundleID = focused.app.bundleIdentifier ?? "unknown"
            let focusedTab = tab(bundleID, windows.first { $0.id == focused.id }?.bounds)
            let focus: Focus
            switch decide(bundleID, focusedTab) {
            case .blocked: focus = .hidden(windowID: focused.id, reason: .blocked)
            case .neverRead: focus = .hidden(windowID: focused.id, reason: .neverRead)
            case .read:
                // A Chrome window we could not match to a tab might be incognito, so its title is not kept.
                let title = bundleID == Permissions.chromeBundleID && focusedTab == nil
                    ? nil : focusedTab?.title ?? focused.window.flatMap { AX.attr($0, kAXTitleAttribute) as? String }
                focus = Focus(windowID: focused.id, bundleID: bundleID, appName: focused.app.localizedName ?? "", title: title)
            }
            if focus != lastFocus {
                lastFocus = focus
                write(.focus, focus)
            }
        }

        let screens = Windows.screenRects()
        var layout = Layout(screens: screens, windows: [])
        var matchStats = Windows.Match()
        defer {
            if layouts.changed(layout) { write(.layout, layout) }
            if matchStats.windows.count < layout.windows.filter({ $0.hidden == nil }).count {
                log.debug("matched \(matchStats.byID) by id, \(matchStats.byFrame) by frame, \(matchStats.byElimination) by elimination; unmatched \(self.unmatched.count)")
            }
        }

        var axByPid: [pid_t: [CGWindowID: AXUIElement]] = [:]
        for w in windows {
            let app = NSRunningApplication(processIdentifier: w.pid)
            let bundleID = app?.bundleIdentifier ?? "unknown"
            if Windows.systemOverlays.contains(bundleID) { continue }
            let tab = tab(bundleID, w.bounds)
            let decision = decide(bundleID, tab)
            let hiddenReason: Gap.Reason? = switch decision {
            case .read: nil
            case .blocked: .blocked
            case .neverRead: .neverRead
            }
            layout.windows.append(Layout.Window(
                windowID: w.id, bundleID: hiddenReason == nil ? bundleID : "", appName: hiddenReason == nil ? (app?.localizedName ?? w.owner) : "",
                frame: w.bounds, screen: Layout.screen(for: w.bounds, in: screens), visible: Layout.roundedVisible(w.visibleFraction),
                focused: w.id == focused?.id, hidden: hiddenReason))

            // 不看名单 and never-read windows: one placeholder, no title, no text, no accessibility call at all.
            if let reason = hiddenReason {
                if hidden[w.id] != reason {
                    hidden[w.id] = reason
                    history.forget(window: w.id)
                    write(.gap, Gap(reason: reason, windowID: w.id))
                }
                continue
            }
            hidden[w.id] = nil

            if !flagged.contains(w.pid) {
                flagged.insert(w.pid)
                Windows.enableAccessibility(pid: w.pid, bundleID: bundleID, bundleURL: app?.bundleURL)
            }
            if axByPid[w.pid] == nil {
                let match = Windows.axWindows(pid: w.pid, screenWindows: windows.filter { $0.pid == w.pid })
                axByPid[w.pid] = match.windows
                matchStats.byID += match.byID
                matchStats.byFrame += match.byFrame
                matchStats.byElimination += match.byElimination
                matchStats.windows.merge(match.windows) { a, _ in a }
            }
            // On screen but not in the app's accessibility tree: keep the hole visible instead of dropping the window.
            guard let axWindow = axByPid[w.pid]?[w.id] else {
                if unmatched.insert(w.id).inserted {
                    write(.gap, Gap(reason: .noAccessibilityWindow, bundleID: bundleID, appName: app?.localizedName ?? w.owner, windowID: w.id))
                }
                continue
            }
            unmatched.remove(w.id)

            let title = tab?.title ?? (AX.attr(axWindow, kAXTitleAttribute) as? String)
            let read = AXWalker.read(window: axWindow, windowFrame: w.bounds)
            let text = VisibleText.extract(read.root, windowFrame: w.bounds)
            log.debug("read \(bundleID, privacy: .public): \(read.nodes) nodes, \(read.ms, format: .fixed(precision: 0)) ms, truncated \(read.truncated), \(text.visibleChars) visible")
            var body = WindowText(windowID: w.id, bundleID: bundleID, appName: app?.localizedName ?? w.owner, title: title,
                                  focused: w.id == focused?.id, method: .accessibility, url: tab?.url, added: [],
                                  lineCount: text.lines.count, visibleChars: text.visibleChars, truncated: read.truncated)

            if Self.compareOCR, body.focused, Date().timeIntervalSince(lastCompare) > 60 {
                lastCompare = Date()
                let visible = text.visibleChars, log = self.log
                Task.detached(priority: .utility) {
                    let ocr = await OCR.read(windowID: w.id, bounds: w.bounds)?.reduce(0) { $0 + $1.count } ?? -1
                    log.notice("compare \(bundleID, privacy: .public): accessibility \(visible) visible, OCR \(ocr)")
                }
            }
            if text.visibleChars < Self.ocrThreshold, w.visibleFraction > 0.3 {
                fallBackToOCR(window: w, body: body)
                continue
            }
            unreadable.remove(w.id)
            if let added = history.added(window: w.id, lines: text.lines, partial: read.truncated), !added.isEmpty {
                body.added = added
                write(.windowText, body)
            }
        }
    }

    private func fallBackToOCR(window w: ScreenWindow, body: WindowText) {
        guard options.ocrEnabled, CGPreflightScreenCaptureAccess() else { return markUnreadable(w, body) }
        guard !ocrPending.contains(w.id) else { return }
        guard ocrBudget.take(window: w.id, now: Date()) else { return }
        ocrPending.insert(w.id)
        Task.detached(priority: .utility) {
            let lines = await OCR.read(windowID: w.id, bounds: w.bounds)
            self.queue.async {
                self.ocrPending.remove(w.id)
                guard self.dayID != nil, !self.paused else { return }
                guard let lines, !lines.isEmpty else { return self.markUnreadable(w, body) }
                self.unreadable.remove(w.id)
                var body = body
                body.method = .ocr
                body.lineCount = lines.count
                body.visibleChars = lines.reduce(0) { $0 + $1.count }
                body.truncated = false
                if let added = self.history.added(window: w.id, lines: lines), !added.isEmpty {
                    body.added = added
                    self.write(.windowText, body)
                }
            }
        }
    }

    /// Records the hole once per window until it becomes readable again.
    private func markUnreadable(_ w: ScreenWindow, _ body: WindowText) {
        guard unreadable.insert(w.id).inserted else { return }
        write(.gap, Gap(reason: .unreadable, bundleID: body.bundleID, appName: body.appName, windowID: w.id))
    }

    private func write<Body: Encodable>(_ kind: RecordKind, _ body: Body) {
        guard let dayID else { return }
        do {
            writes.yield(try Record(dayID: dayID, at: Date(), kind: kind, body: body))
        } catch {
            log.error("encoding \(kind.rawValue, privacy: .public) failed: \(error, privacy: .public)")
        }
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    static func secondsSinceInput() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }
}
