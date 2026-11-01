import Foundation

/// What happened in one window during one stretch (about a minute). Facts only; whether that means
/// "waiting for a reply" or "reading" is left to the AI (#14).
public struct Activity: Codable, Sendable, Equatable {
    public var windowID: UInt32
    public var bundleID: String
    public var appName: String
    public var place: Place?
    public var from: Date
    public var to: Date
    /// Seconds this window was the focused one.
    public var focusedSeconds: Int = 0
    /// Characters added to and removed from the focused text field, from the field's length; keys are never read.
    public var typedChars: Int = 0
    public var deletedChars: Int = 0
    /// Times a non-empty text field became empty, which is usually sending.
    public var fieldCleared: Int = 0
    /// Characters of new text that appeared in the window, focused or not.
    public var contentAddedChars: Int = 0
    /// Roughly how long the user scrolled with the pointer over this window. A trackpad swipe sends dozens of
    /// events, so time says more than an event count. No positions are kept.
    public var scrollSeconds: Int = 0
    /// Clicks while the pointer was over this window.
    public var clicks: Int = 0
    /// Focused seconds with no typing, scrolling, clicking or new content.
    public var stillSeconds: Int = 0

    public init(windowID: UInt32, bundleID: String, appName: String, place: Place?, from: Date, to: Date) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.appName = appName
        self.place = place
        self.from = from
        self.to = to
    }

    public var isEmpty: Bool {
        focusedSeconds == 0 && typedChars == 0 && deletedChars == 0 && fieldCleared == 0 && contentAddedChars == 0
            && scrollSeconds == 0 && clicks == 0
    }
}

/// One sample's worth of facts about one window, fed to `ActivityTracker`.
public struct ActivitySample: Sendable {
    public var windowID: UInt32
    public var bundleID: String
    public var appName: String
    public var place: Place?
    public var focused = false
    public var typed = 0
    public var deleted = 0
    public var cleared = 0
    public var contentAdded = 0
    public var scrolls = 0
    public var clicks = 0

    public init(windowID: UInt32, bundleID: String, appName: String, place: Place?) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.appName = appName
        self.place = place
    }
}

/// Adds samples into per-window buckets and hands them out once a bucket is `bucket` seconds old.
public struct ActivityTracker: Sendable {
    public var bucket: TimeInterval
    private var start: Date?
    private var windows: [UInt32: Activity] = [:]
    private var order: [UInt32] = []

    public init(bucket: TimeInterval = 60) { self.bucket = bucket }

    /// Records `seconds` of time ending at `now` for each sample. Returns finished buckets, if any.
    public mutating func add(_ samples: [ActivitySample], seconds: TimeInterval, now: Date) -> [Activity] {
        if start == nil { start = now.addingTimeInterval(-seconds) }
        let dt = Int(seconds.rounded())
        for s in samples {
            if windows[s.windowID] == nil {
                order.append(s.windowID)
                windows[s.windowID] = Activity(windowID: s.windowID, bundleID: s.bundleID, appName: s.appName, place: s.place,
                                                from: start ?? now, to: now)
            }
            var a = windows[s.windowID]!
            a.place = s.place ?? a.place
            a.to = now
            if s.focused { a.focusedSeconds += dt }
            a.typedChars += s.typed
            a.deletedChars += s.deleted
            a.fieldCleared += s.cleared
            a.contentAddedChars += s.contentAdded
            if s.scrolls > 0 { a.scrollSeconds += dt }
            a.clicks += s.clicks
            if s.focused, s.typed == 0, s.deleted == 0, s.cleared == 0, s.contentAdded == 0, s.scrolls == 0, s.clicks == 0 {
                a.stillSeconds += dt
            }
            windows[s.windowID] = a
        }
        guard let start, now.timeIntervalSince(start) >= bucket else { return [] }
        return flush(now: now)
    }

    /// Hands out everything collected so far, e.g. when recording stops.
    public mutating func flush(now: Date) -> [Activity] {
        let done = order.compactMap { windows[$0] }.filter { !$0.isEmpty }.map { a -> Activity in
            var a = a
            a.to = now
            return a
        }
        start = now
        windows = [:]
        order = []
        return done
    }
}

/// Turns the focused text field into typed, deleted and cleared counts, per window, and hands back the text
/// that was in the field when it was cleared, which is usually what the user sent (FR-25).
public struct FieldTracker: Sendable {
    public struct Change: Equatable, Sendable {
        public var typed = 0
        public var deleted = 0
        public var cleared = 0
        /// The field's text just before it was cleared.
        public var sent: String?
    }

    private var texts: [UInt32: String] = [:]

    public init() {}

    /// `text` is nil when the focus is not in a text field; the last known text is then kept.
    public mutating func update(window: UInt32, text: String?) -> Change {
        guard let text else { return Change() }
        defer { texts[window] = text }
        guard let before = texts[window] else { return Change() }
        let (now, was) = (text.count, before.count)
        if now > was { return Change(typed: now - was) }
        // Cleared (usually sent): most of the text vanished at once. The field may then show a placeholder, so 0 is not required.
        if now < was {
            let cleared = was >= 5 && now * 5 <= was
            let sent = before.trimmingCharacters(in: .whitespacesAndNewlines)
            return Change(deleted: was - now, cleared: cleared ? 1 : 0, sent: cleared && !sent.isEmpty ? sent : nil)
        }
        return Change()
    }

    public mutating func reset() { texts = [:] }
}
