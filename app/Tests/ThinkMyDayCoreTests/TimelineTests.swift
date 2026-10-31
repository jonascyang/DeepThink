import CoreGraphics
import Foundation
import Testing
@testable import ThinkMyDayCore

@Suite struct TimelineTests {
    let day = UUID()
    let t0 = Date(timeIntervalSince1970: 1_793_400_000)

    private func record<Body: Encodable>(_ seconds: Double, _ kind: RecordKind, _ body: Body) throws -> Record {
        try Record(dayID: day, at: t0.addingTimeInterval(seconds), kind: kind, body: body)
    }

    @Test func describesEveryKindInOrder() throws {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)]
        let records = [
            try record(60, .windowText, WindowText(windowID: 1, bundleID: "com.google.Chrome", appName: "Google Chrome", title: "稳定币研究",
                                                   focused: true, method: .accessibility, url: "https://example.com/a",
                                                   added: ["第一段", "第二段"], lineCount: 2, visibleChars: 6, truncated: false)),
            try record(0, .presence, Presence(state: .recordingStarted, since: t0)),
            try record(30, .focus, Focus(windowID: 1, bundleID: "com.google.Chrome", appName: "Google Chrome", title: "稳定币研究")),
            try record(45, .layout, Layout(screens: screens, windows: [
                Layout.Window(windowID: 1, bundleID: "com.google.Chrome", appName: "Google Chrome", frame: screens[0], screen: 0, visible: 1, focused: true),
                Layout.Window(windowID: 2, bundleID: "", appName: "", frame: screens[1], screen: 1, visible: 1, focused: false, hidden: .blocked),
            ])),
            try record(90, .windowText, WindowText(windowID: 3, bundleID: "x", appName: "某 App", title: nil, focused: false, method: .ocr,
                                                   added: ["识别出的字"], lineCount: 1, visibleChars: 5, truncated: true)),
        ]
        let entries = Timeline.entries(records)
        #expect(entries.map(\.headline) == ["开始记录", "焦点：Google Chrome", "布局：2 块屏幕，2 个可见窗口", "Google Chrome", "某 App"])
        #expect(entries[2].detail == "屏幕 1：Google Chrome（焦点） · 屏幕 2：不看")
        #expect(entries[3].detail == "稳定币研究 · https://example.com/a · 焦点")
        #expect(entries[3].lines == ["第一段", "第二段"])
        #expect(entries[4].detail == "同时可见 · OCR 识别 · 只读到一部分")
        #expect(entries[3].style == .content)
    }

    @Test func hiddenWindowsShowNothingButThePlaceholder() throws {
        let entries = Timeline.entries([
            try record(0, .gap, Gap(reason: .blocked, windowID: 9)),
            try record(1, .focus, Focus.hidden(windowID: 9, reason: .blocked)),
            try record(2, .gap, Gap(reason: .neverRead, windowID: 10)),
        ])
        #expect(entries.map(\.headline) == ["不看名单里的窗口", "焦点切到不看名单里的窗口", "永不读取的窗口"])
        #expect(entries.allSatisfy { $0.style == .hidden && $0.lines.isEmpty })
    }

    @Test func gapsAndAbsencesAreShownNotFilled() throws {
        let entries = Timeline.entries([
            try record(0, .presence, Presence(state: .recordingStarted, since: t0)),
            try record(400, .presence, Presence(state: .idle, since: t0.addingTimeInterval(200))),
            try record(500, .presence, Presence(state: .active, since: t0.addingTimeInterval(500))),
            try record(600, .gap, Gap(reason: .unreadable, bundleID: "x", appName: "某 App", windowID: 3)),
            try record(700, .gap, Gap(reason: .noAccessibilityWindow, bundleID: "y", appName: "另一个 App", windowID: 4)),
            try record(800, .presence, Presence(state: .locked, since: t0.addingTimeInterval(800))),
            try record(900, .presence, Presence(state: .unlocked, since: t0.addingTimeInterval(900))),
            try record(1000, .gap, Gap(reason: .noAccessibilityPermission)),
        ])
        #expect(entries.map(\.headline) == ["开始记录", "无输入", "恢复输入", "读不到文字，OCR 也没有结果",
                                            "窗口在屏幕上，但辅助功能里找不到它", "锁屏，停止读取", "解锁，继续读取", "没有辅助功能权限，读不到窗口"])
        #expect(entries[1].time == t0.addingTimeInterval(200), "无输入 is dated from the last input")
        #expect(entries.filter { $0.style == .gap }.count == 5)
    }

    @Test func secondStartWithoutStopMarksAnInterruption() throws {
        let entries = Timeline.entries([
            try record(0, .presence, Presence(state: .recordingStarted, since: t0)),
            try record(3600, .presence, Presence(state: .recordingStarted, since: t0.addingTimeInterval(3600))),
            try record(7200, .presence, Presence(state: .recordingStopped, since: t0.addingTimeInterval(7200))),
            try record(9000, .presence, Presence(state: .recordingStarted, since: t0.addingTimeInterval(9000))),
        ])
        #expect(entries.map(\.headline) == ["开始记录", "记录中断：App 没有正常退出", "开始记录", "停止记录", "开始记录"])
    }

    @Test func unknownAndBrokenRecordsAreVisible() {
        let entries = Timeline.entries([
            Record(dayID: day, at: t0, kind: "fromTheFuture", body: Data("{}".utf8)),
            Record(dayID: day, at: t0.addingTimeInterval(1), kind: "windowText", body: Data("not json".utf8)),
        ])
        #expect(entries.map(\.headline) == ["未知的记录类型：fromTheFuture", "无法解读的记录"])
    }
}
