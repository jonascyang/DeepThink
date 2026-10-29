import AppKit
import ApplicationServices
import Foundation

struct CGWin {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let bounds: CGRect
}

/// Takes one snapshot of every visible window: layout, focus and AX-readable text statistics.
final class Sampler {
    let queue = DispatchQueue(label: "m0b.sampler")
    var ocr: OCRProbe?

    private var busy = false
    private var lastLines: [CGWindowID: Set<Int>] = [:]
    private var flaggedApps: [pid_t: String] = [:]
    private var lastCompareOCR = Date.distantPast

    static let systemOverlays: Set<String> = ["com.apple.WindowManager", "com.apple.controlcenter", "com.apple.notificationcenterui"]
    static let chromiumBundles: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.openai.atlas",
    ]
    static let passwordManagers: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.lastpass.LastPass", "com.apple.Passwords", "com.apple.keychainaccess", "com.dashlane.dashlanephonefinal",
    ]

    private(set) var sampleCount = 0
    private(set) var skippedBusy = 0

    func trigger(_ reason: String) {
        queue.async {
            if self.busy { self.skippedBusy += 1; return }
            self.busy = true
            defer { self.busy = false }
            self.sample(trigger: reason)
        }
    }

    // MARK: - Sampling

    private func sample(trigger: String) {
        let start = DispatchTime.now().uptimeNanoseconds
        let trusted = AXIsProcessTrusted()
        let front = NSWorkspace.shared.frontmostApplication
        let wins = Self.onScreenWindows()
        let screens = Self.screenRects()

        var focusedID: CGWindowID?
        if trusted, let front {
            let app = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.3)
            if let fw = AX.attr(app, kAXFocusedWindowAttribute) {
                focusedID = AX.windowID(fw as! AXUIElement)
            }
        }

        // Group AX windows per process once per sample.
        var axWindows: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var obs: [WindowObs] = []
        var newFlags: [(pid_t, String, String)] = []

        for (index, w) in wins.enumerated() {
            let visible = Self.visibleFraction(of: w, occluders: Array(wins[..<index]), screens: screens)
            if visible < 0.05 { continue }
            let running = NSRunningApplication(processIdentifier: w.pid)
            let bundle = running?.bundleIdentifier ?? "unknown"
            if Self.systemOverlays.contains(bundle) { continue }
            var o = WindowObs(
                bundleId: bundle, app: running?.localizedName ?? w.owner,
                focused: w.id == focusedID, visibleFraction: (visible * 100).rounded() / 100,
                screen: Self.screenIndex(for: w.bounds, screens: screens),
                width: Int(w.bounds.width), height: Int(w.bounds.height), titleLength: 0,
                axMatched: false, axChars: 0, axVisibleChars: 0, axNodes: 0, axMs: 0, truncated: false,
                newChars: 0, newCJK: 0, flagApplied: flaggedApps[w.pid], skipped: nil)

            if Self.passwordManagers.contains(bundle) {
                o.skipped = "password-manager"
                obs.append(o)
                continue
            }
            guard trusted else {
                o.skipped = "no-ax-permission"
                obs.append(o)
                continue
            }

            if axWindows[w.pid] == nil {
                axWindows[w.pid] = Self.axWindowMap(pid: w.pid, cgWindows: wins.filter { $0.pid == w.pid })
            }
            if let axWin = axWindows[w.pid]?[w.id] {
                o.axMatched = true
                o.titleLength = (AX.attr(axWin, kAXTitleAttribute) as? String)?.count ?? 0
                let r = AXReader.read(window: axWin, windowFrame: w.bounds)
                o.axChars = r.chars
                o.axVisibleChars = r.visibleChars
                o.axNodes = r.nodes
                o.axMs = (r.ms * 10).rounded() / 10
                o.truncated = r.truncated

                let hashes = Set(r.lines.map { $0.hashValue })
                let previous = lastLines[w.id] ?? []
                for line in r.lines where !previous.contains(line.hashValue) {
                    o.newChars += line.count
                    o.newCJK += TextStats.cjkCount(line)
                }
                lastLines[w.id] = hashes

                if flaggedApps[w.pid] == nil, let flavor = Self.flavor(bundle: bundle, app: running) {
                    newFlags.append((w.pid, bundle, flavor))
                }
                maybeOCR(window: w, bundle: bundle, focused: o.focused, axVisibleChars: r.visibleChars, visible: visible)
            }
            obs.append(o)
        }

        // Turn on accessibility for Electron / Chromium apps after their first, unflagged read,
        // so the record holds a before/after comparison.
        for (pid, bundle, flavor) in newFlags where flaggedApps[pid] == nil {
            let before = obs.filter { $0.bundleId == bundle }.map(\.axVisibleChars).reduce(0, +)
            let app = AXUIElementCreateApplication(pid)
            var attribute = "AXManualAccessibility"
            var err = AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue)
            if err != .success, flavor == "chromium" {
                attribute = "AXEnhancedUserInterface"
                err = AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue)
            }
            flaggedApps[pid] = flavor
            RecordStore.shared.append(FlagRec(ts: Date().timeIntervalSince1970, bundleId: bundle, flavor: flavor,
                                              attribute: attribute, axError: err.rawValue, charsBefore: before))
        }

        let ms = AXReader.elapsedMs(since: start)
        sampleCount += 1
        RecordStore.shared.append(SampleRec(ts: Date().timeIntervalSince1970, ms: (ms * 10).rounded() / 10, trigger: trigger,
                                            axTrusted: trusted, frontBundle: front?.bundleIdentifier,
                                            screens: screens.count, windows: obs))
    }

    private func maybeOCR(window: CGWin, bundle: String, focused: Bool, axVisibleChars: Int, visible: Double) {
        guard let ocr else { return }
        if axVisibleChars < 50, visible > 0.3 {
            ocr.request(window: window, bundle: bundle, reason: "fallback", axVisibleChars: axVisibleChars)
        } else if focused, Date().timeIntervalSince(lastCompareOCR) > 300 {
            lastCompareOCR = Date()
            ocr.request(window: window, bundle: bundle, reason: "compare", axVisibleChars: axVisibleChars)
        }
    }

    // MARK: - Windows and screens

    /// Normal-layer windows on screen, front to back, excluding this process.
    static func onScreenWindows() -> [CGWin] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { d in
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let bd = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: bd),
                  bounds.width >= 80, bounds.height >= 60,
                  (d[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { return nil }
            return CGWin(id: id, pid: pid, owner: d[kCGWindowOwnerName as String] as? String ?? "", bounds: bounds)
        }
    }

    /// Screen frames in CG global coordinates (origin at the top-left of the primary screen).
    static func screenRects() -> [CGRect] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let h = primary.frame.height
        return screens.map { s in
            CGRect(x: s.frame.minX, y: h - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
    }

    static func screenIndex(for r: CGRect, screens: [CGRect]) -> Int {
        let c = CGPoint(x: r.midX, y: r.midY)
        return screens.firstIndex { $0.contains(c) } ?? -1
    }

    /// Fraction of the window that is on a screen and not covered by windows in front of it (20×20 grid estimate).
    static func visibleFraction(of w: CGWin, occluders: [CGWin], screens: [CGRect]) -> Double {
        let n = 20
        var visible = 0
        for i in 0..<n {
            for j in 0..<n {
                let p = CGPoint(x: w.bounds.minX + (Double(i) + 0.5) * w.bounds.width / Double(n),
                                y: w.bounds.minY + (Double(j) + 0.5) * w.bounds.height / Double(n))
                guard screens.contains(where: { $0.contains(p) }) else { continue }
                if !occluders.contains(where: { $0.bounds.contains(p) }) { visible += 1 }
            }
        }
        return Double(visible) / Double(n * n)
    }

    /// Maps CG window ids to AX window elements; falls back to frame matching when the id lookup fails.
    static func axWindowMap(pid: pid_t, cgWindows: [CGWin]) -> [CGWindowID: AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let list = AX.attr(app, kAXWindowsAttribute) as? [AXUIElement] else { return [:] }
        var map: [CGWindowID: AXUIElement] = [:]
        for el in list {
            if let id = AX.windowID(el) {
                map[id] = el
            } else if let f = AX.frame(el), let match = cgWindows.first(where: { $0.bounds.equalTo(f) && map[$0.id] == nil }) {
                map[match.id] = el
            }
        }
        return map
    }

    static func flavor(bundle: String, app: NSRunningApplication?) -> String? {
        if chromiumBundles.contains(bundle) { return "chromium" }
        if let url = app?.bundleURL?.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"),
           FileManager.default.fileExists(atPath: url.path) { return "electron" }
        return nil
    }
}
