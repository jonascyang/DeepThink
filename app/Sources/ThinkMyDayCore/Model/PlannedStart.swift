import Foundation

/// 计划开始时刻: "my day usually starts at 9:00", in the user's time zone.
public struct PlannedStart: Codable, Sendable, Equatable {
    public var hour: Int
    public var minute: Int
    public var timeZoneID: String

    public init(hour: Int, minute: Int, timeZone: TimeZone = .current) {
        self.hour = hour
        self.minute = minute
        self.timeZoneID = timeZone.identifier
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// "9:00"
    public var clockText: String { String(format: "%d:%02d", hour, minute) }

    /// The planned start nearest to `reference`: yesterday's, today's or tomorrow's.
    /// Opening at 00:30 with a 23:00 plan counts as 1 h 30 m late, not 22 h 30 m early.
    public func occurrence(near reference: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: reference)
        let candidates = (-1...1).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        return candidates.min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) } ?? reference
    }
}

/// Neutral wording for how a start compares with the plan. No judgement, per PRD §5.2.
public enum PlanComparison {
    /// "比计划晚 1 小时 30 分", "比计划早 20 分", "和计划一致".
    public static func text(start: Date, planned: Date) -> String {
        let minutes = Int((start.timeIntervalSince(planned) / 60).rounded())
        if minutes == 0 { return "和计划一致" }
        return "比计划\(minutes > 0 ? "晚" : "早") \(duration(abs(minutes)))"
    }

    /// "1 小时 30 分", "2 小时", "20 分"
    public static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) 分"
        case (_, 0): return "\(h) 小时"
        default: return "\(h) 小时 \(m) 分"
        }
    }
}

/// What the menu bar shows: 未开启 ○, 记录中 ●, 已结束 ✓ (docs/UI-构思.md).
public enum DayStatus: Equatable, Sendable {
    /// `lateMinutes` is set only when there is a plan and it has passed.
    case notStarted(lateMinutes: Int?)
    case recording(ReviewDay)
    /// The most recent day ended earlier on the same calendar day as `now`.
    case ended(ReviewDay)

    public static func current(open: ReviewDay?, last: ReviewDay?, plan: PlannedStart?, now: Date) -> DayStatus {
        if let open { return .recording(open) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = plan?.timeZone ?? .current
        if let last, let ended = last.endedAt, calendar.isDate(ended, inSameDayAs: now) { return .ended(last) }
        guard let plan else { return .notStarted(lateMinutes: nil) }
        let minutes = Int(now.timeIntervalSince(plan.occurrence(near: now)) / 60)
        return .notStarted(lateMinutes: minutes > 0 ? minutes : nil)
    }
}
