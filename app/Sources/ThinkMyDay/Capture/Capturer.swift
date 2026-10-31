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
    /// Apps that posted an accessibility change since the last sample; their focused window may OCR before its 30 s.
    private var changedPids: Set<pid_t> = []
    private var unreadable: Set<CGWindowID> = []
    /// Windows currently left unread, so the placeholder is written once per stretch, not every sample.
    private var hidden: [CGWindowID: Gap.Reason] = [:]
    private var unmatched: Set<CGWindowID> = []
    private var layouts = LayoutTracker()
    private var activity = ActivityTracker()
    private var fields = FieldTracker()
    private var files = OpenedFileHistory()
    private var counters: InputCounters?
    private var lastSample: Date?
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
            self.activity = ActivityTracker()
            self.fields.reset()
            self.files.reset()
            self.counters = nil
            self.lastSample = nil
            self.trusted = nil
            self.write(.presence, Presence(state: .recordingStarted, since: Date()))
        }
        trigger()
    }

    /// At quit: writes 停止记录 straight to the store and waits for it, so the timeline can tell a normal quit
    /// from a crash. (Ending the day needs no such record; the day's end time says it.)
    func finish() async {
        let (dayID, pending): (UUID?, [Activity]) = queue.sync {
            let id = self.dayID
            let pending = self.activity.flush(now: Date())
            self.dayID = nil
            return (id, pending)
        }
        guard let dayID else { return }
        for a in pending {
            if let record = try? Record(dayID: dayID, at: a.to, kind: .activity, body: a) { _ = try? await store.append(.recordCaptured(record)) }
        }
        guard let record = try? Record(dayID: dayID, at: Date(), kind: .presence,
                                                  body: Presence(state: .recordingStopped, since: Date())) else { return }
        do { try await store.append(.recordCaptured(record)) } catch { log.error("stop record failed: \(error, privacy: .public)") }
    }

    func stop() { queue.async { self.dayID = nil; self.history.reset(); self.activity = ActivityTracker() } }

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

    /// The frontmost app reported a focus, title or value change.
    func noteChange(pid: pid_t) {
        queue.async { self.changedPids.insert(pid) }
    }

    /// Takes a sample now unless one is running.
    func trigger() {
        let bundles = Set(Windows.visible().compactMap { NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier })
        // AppleScript runs on the main thread; ask Chrome and Finder here and hand the answers to the queue.
        func onMain<T: Sendable>(_ body: @MainActor () -> T) -> T {
            Thread.isMainThread ? MainActor.assumeIsolated(body) : DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
        }
        let tabs = bundles.contains(Permissions.chromeBundleID) ? onMain { Chrome.activeTabs() } : []
        // Finder paths through AppleScript are switched off for now (Jonas 2026-10-31): it needs one more permission.
        // Finder selections keep only the names accessibility gives.
        let finder = Finder.enabled && bundles.contains(Finder.bundleID) ? onMain { Finder.state() } : Finder.State()
        queue.async {
            guard !self.busy else { return }
            self.busy = true
            defer { self.busy = false }
            self.sample(chromeTabs: tabs, finder: finder)
        }
    }

    // MARK: - Sampling (on queue)

    private func sample(chromeTabs: [Chrome.Tab], finder: Finder.State) {
        let changed = changedPids
        changedPids = []
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

        let screens = Windows.screenRects()
        let place = { (frame: CGRect) in Place(frame: frame, screens: screens) }

        // Time since the last sample, and the scrolls and clicks in it, credited to the window under the pointer.
        let dt = min(lastSample.map { now.timeIntervalSince($0) } ?? 0, 30)
        lastSample = now
        let counts = InputCounters.now()
        let scrolls = counters.map { Int(counts.scrolls &- $0.scrolls) } ?? 0
        let clicks = counters.map { Int(counts.clicks &- $0.clicks) } ?? 0
        counters = counts
        let pointer = InputCounters.pointer(screens: screens)
        let underPointer = windows.first { $0.bounds.contains(pointer) }?.id
        var samples: [CGWindowID: ActivitySample] = [:]

        let focused = Windows.focused()
        let focusGained = focused?.id != nil && focused?.id != lastFocus?.windowID
        if let focused {
            let bundleID = focused.app.bundleIdentifier ?? "unknown"
            let appName = focused.app.localizedName ?? ""
            let frame = windows.first { $0.id == focused.id }?.bounds
            let focusedTab = tab(bundleID, frame)
            let focusPlace = frame.map(place)
            let focus: Focus
            switch decide(bundleID, focusedTab) {
            case .blocked: focus = .hidden(windowID: focused.id, reason: .blocked, bundleID: bundleID, appName: appName, place: focusPlace)
            case .neverRead: focus = .hidden(windowID: focused.id, reason: .neverRead, bundleID: bundleID, appName: appName, place: focusPlace)
            case .read:
                // A Chrome window we could not match to a tab might be incognito, so its title is not kept.
                let title = bundleID == Permissions.chromeBundleID && focusedTab == nil
                    ? nil : focusedTab?.title ?? focused.window.flatMap { AX.attr($0, kAXTitleAttribute) as? String }
                focus = Focus(windowID: focused.id, bundleID: bundleID, appName: appName, title: title, place: focusPlace)
            }
            if focus != lastFocus {
                lastFocus = focus
                write(.focus, focus)
            }
        }

        var layout = Layout(screens: screens, windows: [])
        var matchStats = Windows.Match()
        defer {
            if layouts.changed(layout) { write(.layout, layout) }
            if matchStats.windows.count < layout.windows.filter({ $0.hidden == nil }).count {
                log.debug("matched \(matchStats.byID) by id, \(matchStats.byFrame) by frame, \(matchStats.byElimination) by elimination; unmatched \(self.unmatched.count)")
            }
            for a in activity.add(Array(samples.values), seconds: dt, now: now) { write(.activity, a, at: a.to) }
        }

        var axByPid: [pid_t: [CGWindowID: AXUIElement]] = [:]
        for w in windows {
            let app = NSRunningApplication(processIdentifier: w.pid)
            let bundleID = app?.bundleIdentifier ?? "unknown"
            let appName = app?.localizedName ?? w.owner
            if Windows.systemOverlays.contains(bundleID) || Windows.systemOverlayOwners.contains(w.owner) { continue }
            let tab = tab(bundleID, w.bounds)
            let decision = decide(bundleID, tab)
            let hiddenReason: Gap.Reason? = switch decision {
            case .read: nil
            case .blocked: .blocked
            case .neverRead: .neverRead
            }
            let windowPlace = place(w.bounds)
            let isFocused = w.id == focused?.id
            layout.windows.append(Layout.Window(
                windowID: w.id, bundleID: bundleID, appName: appName, frame: w.bounds, screen: windowPlace.screen,
                visible: Layout.roundedVisible(w.visibleFraction), focused: isFocused, hidden: hiddenReason))

            var sample = ActivitySample(windowID: w.id, bundleID: bundleID, appName: appName, place: windowPlace)
            sample.focused = isFocused
            if w.id == underPointer {
                sample.scrolls = scrolls
                sample.clicks = clicks
            }
            defer { samples[w.id] = sample }

            // 不看名单 and never-read windows: the app is kept (#12); no title, no text, no accessibility read.
            if let reason = hiddenReason {
                if hidden[w.id] != reason {
                    hidden[w.id] = reason
                    history.forget(window: w.id)
                    write(.gap, Gap(reason: reason, bundleID: bundleID, appName: appName, windowID: w.id))
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
                    write(.gap, Gap(reason: .noAccessibilityWindow, bundleID: bundleID, appName: appName, windowID: w.id))
                }
                continue
            }
            unmatched.remove(w.id)

            recordFiles(window: w, axWindow: axWindow, bundleID: bundleID, appName: appName, place: windowPlace, finder: finder)

            let title = tab?.title ?? (AX.attr(axWindow, kAXTitleAttribute) as? String)
            let read = AXWalker.read(window: axWindow, windowFrame: w.bounds)
            let text = VisibleText.extract(read.root, windowFrame: w.bounds)
            if isFocused {
                // The app's focused element first; Chromium apps often only mark the field AXFocused inside the tree.
                let length = Files.focusedFieldLength(pid: w.pid) ?? read.root.focusedFieldLength
                if length == nil { log.debug("no focused text field found in \(bundleID, privacy: .public)") }
                (sample.typed, sample.deleted, sample.cleared) = fields.update(window: w.id, length: length)
            }
            log.debug("read \(bundleID, privacy: .public): \(read.nodes) nodes, \(read.ms, format: .fixed(precision: 0)) ms, truncated \(read.truncated), \(text.visibleChars) visible")
            var body = WindowText(windowID: w.id, bundleID: bundleID, appName: appName, title: title,
                                  focused: isFocused, method: .accessibility, url: tab?.url, added: [],
                                  lineCount: text.lines.count, visibleChars: text.visibleChars, truncated: read.truncated, place: windowPlace)

            if Self.compareOCR, body.focused, Date().timeIntervalSince(lastCompare) > 60 {
                lastCompare = Date()
                let visible = text.visibleChars, log = self.log
                Task.detached(priority: .utility) {
                    let ocr = await OCR.read(windowID: w.id, bounds: w.bounds)?.reduce(0) { $0 + $1.count } ?? -1
                    log.notice("compare \(bundleID, privacy: .public): accessibility \(visible) visible, OCR \(ocr)")
                }
            }
            if text.visibleChars < Self.ocrThreshold, w.visibleFraction > 0.3 {
                let reason: OCRBudget.Reason = !isFocused ? .periodic : focusGained ? .focused : changed.contains(w.pid) ? .changed : .periodic
                fallBackToOCR(window: w, body: body, reason: reason)
                continue
            }
            unreadable.remove(w.id)
            if let added = history.added(window: w.id, lines: text.lines, partial: read.truncated), !added.isEmpty {
                body.added = added
                sample.contentAdded = added.reduce(0) { $0 + $1.count }
                write(.windowText, body)
            }
        }
    }

    /// Writes the files a window shows (its document, or Finder's folder and selection) when they change.
    private func recordFiles(window w: ScreenWindow, axWindow: AXUIElement, bundleID: String, appName: String, place: Place,
                             finder: Finder.State) {
        var found: [(OpenedFile.Source, String)] = []
        let document = Files.document(of: axWindow)
        if bundleID == Finder.bundleID {
            let folder = finder.folder(for: w.bounds) ?? document
            if let folder { found.append((.finderFolder, folder)) }
            // AppleScript gives full paths for the front window's selection; without it, names from accessibility.
            let isFront = finder.windows.first.map { abs($0.bounds.minX - w.bounds.minX) < 2 && abs($0.bounds.minY - w.bounds.minY) < 2 } ?? false
            let selection = isFront && !finder.selection.isEmpty ? finder.selection : Files.finderSelection(in: axWindow, folder: folder)
            found += selection.map { (.finderSelection, $0) }
        } else if let document {
            found.append((.document, document))
        }
        for (source, path) in files.new(window: w.id, files: found) {
            var file = OpenedFile(windowID: w.id, bundleID: bundleID, appName: appName, source: source, path: path,
                                  name: (path as NSString).lastPathComponent)
            file.place = place
            Files.describe(&file)
            write(.file, file)
        }
    }

    private func fallBackToOCR(window w: ScreenWindow, body: WindowText, reason: OCRBudget.Reason) {
        guard options.ocrEnabled, CGPreflightScreenCaptureAccess() else { return markUnreadable(w, body) }
        guard !ocrPending.contains(w.id) else { return }
        guard ocrBudget.take(window: w.id, now: Date(), reason: reason) else { return }
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

    private func write<Body: Encodable>(_ kind: RecordKind, _ body: Body, at: Date = Date()) {
        guard let dayID else { return }
        do {
            writes.yield(try Record(dayID: dayID, at: at, kind: kind, body: body))
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
