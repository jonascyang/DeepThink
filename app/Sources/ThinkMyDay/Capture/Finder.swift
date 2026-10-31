import AppKit

/// Folder and selection of each Finder window, through AppleScript (needs the Automation permission for Finder).
/// Finder's accessibility tree has item names but no paths, so this is the only way to know which file it is (#15).
enum Finder {
    static let bundleID = "com.apple.finder"
    /// Off until Jonas decides to grant Finder automation.
    static let enabled = false

    struct Window: Sendable {
        let bounds: CGRect
        let folder: String?
    }

    struct State: Sendable {
        var windows: [Window] = []
        /// Selected items of the front Finder window.
        var selection: [String] = []

        func folder(for bounds: CGRect) -> String? {
            windows.first { abs($0.bounds.minX - bounds.minX) < 2 && abs($0.bounds.minY - bounds.minY) < 2 }?.folder
        }
    }

    static let maxAge: TimeInterval = 2
    @MainActor private static var cached: (at: Date, state: State)?
    @MainActor private static let script: NSAppleScript? = {
        let script = NSAppleScript(source: source)
        _ = script?.compileAndReturnError(nil)
        return script
    }()

    /// Must run on the main thread. Empty when Finder has no windows or the permission was refused.
    @MainActor
    static func state() -> State {
        if let cached, Date().timeIntervalSince(cached.at) < maxAge { return cached.state }
        var error: NSDictionary?
        var state = State()
        if let result = script?.executeAndReturnError(&error), error == nil, result.numberOfItems == 2,
           let windows = result.atIndex(1), let selection = result.atIndex(2) {
            for i in 0..<windows.numberOfItems {
                guard let row = windows.atIndex(i + 1), row.numberOfItems == 5 else { continue }
                func num(_ k: Int) -> Double { Double(row.atIndex(k)?.int32Value ?? 0) }
                let folder = row.atIndex(5)?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
                state.windows.append(Window(bounds: CGRect(x: num(1), y: num(2), width: num(3) - num(1), height: num(4) - num(2)), folder: folder))
            }
            state.selection = (0..<selection.numberOfItems).compactMap { selection.atIndex($0 + 1)?.stringValue }
        }
        cached = (Date(), state)
        return state
    }

    private static let source = """
    tell application id "com.apple.finder"
        set wins to {}
        repeat with w in Finder windows
            set b to bounds of w
            set p to ""
            try
                set p to POSIX path of (target of w as alias)
            end try
            set end of wins to {item 1 of b, item 2 of b, item 3 of b, item 4 of b, p}
        end repeat
        set sel to {}
        try
            repeat with f in (get selection)
                set end of sel to POSIX path of (f as alias)
            end repeat
        end try
        return {wins, sel}
    end tell
    """
}
