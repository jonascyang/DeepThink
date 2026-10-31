import Foundation

/// Remembers the last lines seen in each window so the same screen is not stored twice.
/// Lines live in memory only.
public struct LineHistory: Sendable {
    private var previous: [UInt32: Set<String>] = [:]

    public init() {}

    /// Lines not present in this window's previous read, in order and without repeats; nil if nothing changed.
    /// A `partial` read stopped at its budget: lines it did not reach are kept as seen, so they are not stored
    /// again when the next read reaches them.
    public mutating func added(window: UInt32, lines: [String], partial: Bool = false) -> [String]? {
        let before = previous[window]
        let current = partial ? Set(lines).union(before ?? []) : Set(lines)
        previous[window] = current
        if before == current { return nil }
        var seen = before ?? []
        return lines.filter { seen.insert($0).inserted }
    }

    public mutating func forget(window: UInt32) { previous[window] = nil }
    public mutating func reset() { previous = [:] }
}

public enum URLCleaner {
    /// Drops the query and fragment, which can carry tokens and personal data (PRD §10).
    public static func clean(_ raw: String) -> String {
        String(raw.prefix { $0 != "?" && $0 != "#" })
    }
}

/// OCR rate limit: each window at most once per `perWindow`, and any OCR at most once per `global`.
public struct OCRBudget: Sendable {
    public var perWindow: TimeInterval = 30
    public var global: TimeInterval = 5
    private var lastWindow: [UInt32: Date] = [:]
    private var lastAny = Date.distantPast

    public init(perWindow: TimeInterval = 30, global: TimeInterval = 5) {
        self.perWindow = perWindow
        self.global = global
    }

    /// Returns true and spends the budget, or false if OCR would run too often.
    public mutating func take(window: UInt32, now: Date) -> Bool {
        guard now.timeIntervalSince(lastAny) >= global,
              now.timeIntervalSince(lastWindow[window] ?? .distantPast) >= perWindow else { return false }
        lastAny = now
        lastWindow[window] = now
        return true
    }
}

/// Turns "seconds since the last input" into idle / active edges. No input is not the same as away (PRD FR-08).
public struct IdleTracker: Sendable {
    public var threshold: TimeInterval
    public private(set) var isIdle = false

    public init(threshold: TimeInterval = 180) { self.threshold = threshold }

    /// Returns a presence change when the state flips. Idle is dated from the last input, not from when it was noticed.
    public mutating func update(secondsSinceInput: TimeInterval, now: Date) -> Presence? {
        let idleNow = secondsSinceInput >= threshold
        guard idleNow != isIdle else { return nil }
        isIdle = idleNow
        return idleNow ? Presence(state: .idle, since: now.addingTimeInterval(-secondsSinceInput)) : Presence(state: .active, since: now)
    }
}
