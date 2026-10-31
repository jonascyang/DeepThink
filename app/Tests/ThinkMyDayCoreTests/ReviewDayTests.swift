import Foundation
import Testing
@testable import ThinkMyDayCore

private func tempStore() throws -> RecordStore {
    try RecordStore(url: FileManager.default.temporaryDirectory
        .appendingPathComponent("tmd-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("thinkmyday.sqlite"), keys: testKeys)
}

/// A wall-clock time in a given zone.
private func at(_ text: String, _ zone: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: zone)
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: text)!
}

@Suite struct PlannedStartTests {
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    @Test func lateOnTheSameDay() {
        let plan = PlannedStart(hour: 9, minute: 0, timeZone: shanghai)
        let start = at("2026-10-31 10:30", "Asia/Shanghai")
        #expect(plan.occurrence(near: start) == at("2026-10-31 09:00", "Asia/Shanghai"))
        #expect(PlanComparison.text(start: start, planned: plan.occurrence(near: start)) == "比计划晚 1 小时 30 分")
    }

    @Test func earlyOnTheSameDay() {
        let plan = PlannedStart(hour: 9, minute: 0, timeZone: shanghai)
        let start = at("2026-10-31 08:40", "Asia/Shanghai")
        #expect(PlanComparison.text(start: start, planned: plan.occurrence(near: start)) == "比计划早 20 分")
    }

    @Test func afterMidnightCountsAgainstYesterdaysLatePlan() {
        let plan = PlannedStart(hour: 23, minute: 0, timeZone: shanghai)
        let start = at("2026-11-01 00:30", "Asia/Shanghai")
        #expect(plan.occurrence(near: start) == at("2026-10-31 23:00", "Asia/Shanghai"))
        #expect(PlanComparison.text(start: start, planned: plan.occurrence(near: start)) == "比计划晚 1 小时 30 分")
    }

    @Test func justBeforeMidnightCountsAgainstTomorrowsEarlyPlan() {
        let plan = PlannedStart(hour: 1, minute: 0, timeZone: shanghai)
        let start = at("2026-10-31 23:00", "Asia/Shanghai")
        #expect(plan.occurrence(near: start) == at("2026-11-01 01:00", "Asia/Shanghai"))
        #expect(PlanComparison.text(start: start, planned: plan.occurrence(near: start)) == "比计划早 2 小时")
    }

    @Test func planUsesItsOwnTimeZone() {
        // 9:00 in New York is 21:00 in Shanghai (EDT, before 2026-11-01).
        let plan = PlannedStart(hour: 9, minute: 0, timeZone: TimeZone(identifier: "America/New_York")!)
        let start = at("2026-10-30 21:00", "Asia/Shanghai")
        #expect(PlanComparison.text(start: start, planned: plan.occurrence(near: start)) == "和计划一致")
    }

    @Test func daylightSavingChangeKeepsWallClockTime() {
        // New York leaves daylight saving on 2026-11-01; 9:00 stays 9:00 local.
        let plan = PlannedStart(hour: 9, minute: 0, timeZone: TimeZone(identifier: "America/New_York")!)
        let start = at("2026-11-02 09:15", "America/New_York")
        #expect(plan.occurrence(near: start) == at("2026-11-02 09:00", "America/New_York"))
    }

    @Test func durationWording() {
        #expect(PlanComparison.duration(5) == "5 分")
        #expect(PlanComparison.duration(120) == "2 小时")
        #expect(PlanComparison.duration(61) == "1 小时 1 分")
    }
}

@Suite struct ReviewDayTests {
    let t0 = Date(timeIntervalSince1970: 1_793_400_000)
    let plan = PlannedStart(hour: 9, minute: 0, timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    @Test func startAndEndADay() async throws {
        let store = try tempStore()
        let (day, ended) = try await store.startDay(at: t0, plannedStart: plan)
        #expect(ended == nil)
        #expect(day.plannedStart == plan.occurrence(near: t0))
        #expect(try await store.openDay() == day)

        let closed = try await store.endDay(at: t0.addingTimeInterval(3600))
        #expect(closed?.id == day.id)
        #expect(try await store.openDay() == nil)
        #expect(try await store.endDay(at: t0.addingTimeInterval(7200)) == nil)
    }

    @Test func forgottenDayEndsWhenTheNextOneStarts() async throws {
        let store = try tempStore()
        let (first, _) = try await store.startDay(at: t0, plannedStart: plan)
        let next = t0.addingTimeInterval(24 * 3600)
        let (second, ended) = try await store.startDay(at: next, plannedStart: plan)

        #expect(ended?.id == first.id)
        #expect(ended?.endedAt == next)
        let days = try await store.days()
        #expect(days.map(\.id) == [first.id, second.id])
        #expect(days[0].endedAt == next)
        #expect(days[1].endedAt == nil)
    }

    @Test func noRecordsOutsideAnOpenDay() async throws {
        let store = try tempStore()
        let (day, _) = try await store.startDay(at: t0, plannedStart: nil)
        try await store.append(.recordCaptured(Record(dayID: day.id, at: t0.addingTimeInterval(1), kind: "windowText", body: Data())))
        try await store.endDay(at: t0.addingTimeInterval(10))

        let late = Record(dayID: day.id, at: t0.addingTimeInterval(11), kind: "windowText", body: Data())
        await #expect(throws: StoreError.dayAlreadyEnded(day.id)) { try await store.append(.recordCaptured(late)) }
        #expect(try await store.records(dayID: day.id).count == 1)
    }

    @Test func dayWithoutPlanHasNoComparison() async throws {
        let store = try tempStore()
        let (day, _) = try await store.startDay(at: t0, plannedStart: nil)
        #expect(day.plannedStart == nil)
    }
}

@Suite struct DayStatusTests {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    var plan: PlannedStart { PlannedStart(hour: 9, minute: 0, timeZone: zone) }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: hour, minute: minute))!
    }

    @Test func lateWhenPlanHasPassed() {
        #expect(DayStatus.current(open: nil, last: nil, plan: plan, now: date(10, 5)) == .notStarted(lateMinutes: 65))
        #expect(DayStatus.current(open: nil, last: nil, plan: plan, now: date(8, 30)) == .notStarted(lateMinutes: nil))
        #expect(DayStatus.current(open: nil, last: nil, plan: nil, now: date(10, 5)) == .notStarted(lateMinutes: nil))
    }

    @Test func recordingWhileADayIsOpen() {
        let day = ReviewDay(startedAt: date(9, 10))
        #expect(DayStatus.current(open: day, last: day, plan: plan, now: date(12, 0)) == .recording(day))
    }

    @Test func endedOnlyUntilTheCalendarDayChanges() {
        let day = ReviewDay(startedAt: date(9, 10), endedAt: date(18, 30))
        #expect(DayStatus.current(open: nil, last: day, plan: plan, now: date(20, 0)) == .ended(day))
        #expect(DayStatus.current(open: nil, last: day, plan: plan, now: date(9, 30).addingTimeInterval(24 * 3600)) == .notStarted(lateMinutes: 30))
    }
}
