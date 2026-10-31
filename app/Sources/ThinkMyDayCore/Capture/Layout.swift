import CoreGraphics
import Foundation

/// 桌面布局: the screens and the windows visible on them at one moment (PRD §6.4).
/// Written when the arrangement changes, so the timeline can say "web page on the left, document on the right".
public struct Layout: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public var windowID: UInt32
        /// Empty for a window that is not read; its frame is kept, its app is not.
        public var bundleID: String
        public var appName: String
        public var frame: CGRect
        /// Index into `screens`, or -1 when the window's centre is on no screen.
        public var screen: Int
        /// Share of the window that is on screen and not covered, 0…1, rounded to 0.05.
        public var visible: Double
        public var focused: Bool
        public var hidden: Gap.Reason?

        public init(windowID: UInt32, bundleID: String, appName: String, frame: CGRect, screen: Int,
                    visible: Double, focused: Bool, hidden: Gap.Reason? = nil) {
            self.windowID = windowID
            self.bundleID = bundleID
            self.appName = appName
            self.frame = frame
            self.screen = screen
            self.visible = visible
            self.focused = focused
            self.hidden = hidden
        }
    }

    /// Screen frames in global coordinates, top-left origin; the first is the main screen.
    public var screens: [CGRect]
    /// Front to back.
    public var windows: [Window]

    public init(screens: [CGRect], windows: [Window]) {
        self.screens = screens
        self.windows = windows
    }

    /// The screen holding the centre of `frame`, or -1.
    public static func screen(for frame: CGRect, in screens: [CGRect]) -> Int {
        screens.firstIndex { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) } ?? -1
    }

    public static func roundedVisible(_ fraction: Double) -> Double { (fraction * 20).rounded() / 20 }
}

/// Decides when a layout is worth a new record. Focus changes alone are not: they have their own `focus` records.
/// Small moves (under `tolerance` points) and visibility wobble are ignored.
public struct LayoutTracker: Sendable {
    public var tolerance: CGFloat = 8
    private var last: Layout?

    public init(tolerance: CGFloat = 8) { self.tolerance = tolerance }

    /// True when `layout` differs from the last one recorded; it then becomes the new reference.
    public mutating func changed(_ layout: Layout) -> Bool {
        defer { if changedFrom(last, layout) { last = layout } }
        return changedFrom(last, layout)
    }

    public mutating func reset() { last = nil }

    private func changedFrom(_ old: Layout?, _ new: Layout) -> Bool {
        guard let old else { return true }
        guard old.screens == new.screens, old.windows.map(\.windowID) == new.windows.map(\.windowID) else { return true }
        for (a, b) in zip(old.windows, new.windows) {
            if a.hidden != b.hidden || a.screen != b.screen || abs(a.visible - b.visible) >= 0.25 { return true }
            if abs(a.frame.minX - b.frame.minX) > tolerance || abs(a.frame.minY - b.frame.minY) > tolerance
                || abs(a.frame.width - b.frame.width) > tolerance || abs(a.frame.height - b.frame.height) > tolerance { return true }
        }
        return false
    }
}
