import AppKit
import ApplicationServices

struct ScreenWindow: Sendable {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let bounds: CGRect
    /// Share of the window that is on a screen and not covered by windows in front of it.
    var visibleFraction: Double = 1
}

enum Windows {
    static let systemOverlays: Set<String> = ["com.apple.WindowManager", "com.apple.controlcenter", "com.apple.notificationcenterui"]

    /// Normal-layer windows on screen, front to back, excluding this process; each with its visible share.
    static func visible() -> [ScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        let all: [ScreenWindow] = list.compactMap { d in
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let bd = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: bd),
                  bounds.width >= 80, bounds.height >= 60,
                  (d[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { return nil }
            return ScreenWindow(id: id, pid: pid, owner: d[kCGWindowOwnerName as String] as? String ?? "", bounds: bounds)
        }
        let screens = screenRects()
        return all.enumerated().map { index, w in
            var w = w
            w.visibleFraction = visibleFraction(of: w, occluders: Array(all[..<index]), screens: screens)
            return w
        }
    }

    /// Screen frames in CG global coordinates (origin at the top-left of the primary screen).
    static func screenRects() -> [CGRect] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let h = primary.frame.height
        return screens.map { CGRect(x: $0.frame.minX, y: h - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
    }

    /// 20×20 grid estimate.
    static func visibleFraction(of w: ScreenWindow, occluders: [ScreenWindow], screens: [CGRect]) -> Double {
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
    static func axWindows(pid: pid_t, screenWindows: [ScreenWindow]) -> [CGWindowID: AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let list = AX.attr(app, kAXWindowsAttribute) as? [AXUIElement] else { return [:] }
        var map: [CGWindowID: AXUIElement] = [:]
        for el in list {
            if let id = AX.windowID(el) {
                map[id] = el
            } else if let f = AX.frame(el), let match = screenWindows.first(where: { $0.bounds.equalTo(f) && map[$0.id] == nil }) {
                map[match.id] = el
            }
        }
        return map
    }

    /// The focused window of the frontmost app.
    static func focused() -> (app: NSRunningApplication, window: AXUIElement?, id: CGWindowID?)? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let raw = AX.attr(app, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return (front, nil, nil) }
        let window = raw as! AXUIElement
        return (front, window, AX.windowID(window))
    }

    static let chromiumBundles: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.openai.atlas",
    ]

    /// Electron and Chromium apps build their accessibility tree only when asked (M0b: Cursor read 0 characters before).
    static func enableAccessibility(pid: pid_t, bundleID: String, bundleURL: URL?) {
        let isElectron = bundleURL.map {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        } ?? false
        guard isElectron || chromiumBundles.contains(bundleID) else { return }
        let app = AXUIElementCreateApplication(pid)
        if AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) != .success, !isElectron {
            _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }
}
