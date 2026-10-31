import AppKit
import ThinkMyDayCore

/// Active-tab URL and title of each Chrome window, through AppleScript (needs the Automation permission).
enum Chrome {
    struct Tab: Sendable {
        let bounds: CGRect
        let title: String
        /// Without query or fragment.
        let url: String
        let incognito: Bool
    }

    /// Results are reused for this long; asking Chrome on every trigger costs more than the URLs are worth.
    static let maxAge: TimeInterval = 5
    @MainActor private static var cached: (at: Date, tabs: [Tab])?
    @MainActor private static let script: NSAppleScript? = {
        let script = NSAppleScript(source: source)
        _ = script?.compileAndReturnError(nil)
        return script
    }()

    /// Must run on the main thread. Returns nothing when Chrome is not running, since a `tell` would launch it.
    @MainActor
    static func activeTabs() -> [Tab] {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Permissions.chromeBundleID).first != nil else { return [] }
        if let cached, Date().timeIntervalSince(cached.at) < maxAge { return cached.tabs }
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error), error == nil else { return [] }
        let tabs: [Tab] = (0..<result.numberOfItems).compactMap { i in
            guard let row = result.atIndex(i + 1), row.numberOfItems == 7 else { return nil }
            func num(_ k: Int) -> Double { Double(row.atIndex(k)?.int32Value ?? 0) }
            let bounds = CGRect(x: num(1), y: num(2), width: num(3) - num(1), height: num(4) - num(2))
            return Tab(bounds: bounds, title: row.atIndex(5)?.stringValue ?? "",
                       url: URLCleaner.clean(row.atIndex(6)?.stringValue ?? ""), incognito: row.atIndex(7)?.stringValue == "incognito")
        }
        cached = (Date(), tabs)
        return tabs
    }

    private static let source = """
    tell application id "com.google.Chrome"
        set out to {}
        repeat with w in windows
            set b to bounds of w
            set end of out to {item 1 of b, item 2 of b, item 3 of b, item 4 of b, title of active tab of w, URL of active tab of w, mode of w}
        end repeat
        return out
    end tell
    """

    /// The tab whose window has these screen bounds (AppleScript bounds match CGWindowList bounds).
    static func tab(for bounds: CGRect, in tabs: [Tab]) -> Tab? {
        tabs.first { abs($0.bounds.minX - bounds.minX) < 2 && abs($0.bounds.minY - bounds.minY) < 2
            && abs($0.bounds.width - bounds.width) < 2 && abs($0.bounds.height - bounds.height) < 2 }
    }
}
