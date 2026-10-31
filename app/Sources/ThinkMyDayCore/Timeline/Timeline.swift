import Foundation

/// One line of the 原始时间线: a record as it was observed, in words, with nothing inferred.
public struct TimelineEntry: Sendable, Equatable, Identifiable {
    public enum Style: Sendable, Equatable {
        /// Text read from a window.
        case content
        case focus
        case layout
        /// A hole: not readable, not permitted, interrupted, away.
        case gap
        /// A window on the 不看名单 or one that is never read.
        case hidden
        /// Input resumed, woke, unlocked, recording started.
        case presence
    }

    public var id: UUID
    public var time: Date
    public var style: Style
    public var headline: String
    /// Window title, URL and how the text was read; may be empty.
    public var detail: String
    /// The new lines of text, for `.content`.
    public var lines: [String]
}

/// Turns records into timeline entries. Pure, so every wording is tested.
public enum Timeline {
    public static func entries(_ records: [Record]) -> [TimelineEntry] {
        var out: [TimelineEntry] = []
        var recording = false
        for record in records.sorted(by: { $0.at < $1.at }) {
            func entry(_ style: TimelineEntry.Style, _ headline: String, _ detail: String = "", _ lines: [String] = [], at: Date? = nil) {
                out.append(TimelineEntry(id: record.id, time: at ?? record.at, style: style, headline: headline, detail: detail, lines: lines))
            }
            switch RecordKind(rawValue: record.kind) {
            case .windowText:
                guard let t = try? record.decode(WindowText.self) else { entry(.gap, "无法解读的记录"); continue }
                let detail = [t.title, t.url, t.focused ? "焦点" : "同时可见", t.method == .ocr ? "OCR 识别" : nil,
                              t.truncated ? "只读到一部分" : nil]
                entry(.content, t.appName, detail.compactMap(nonEmpty).joined(separator: " · "), t.added)
            case .focus:
                guard let f = try? record.decode(Focus.self) else { entry(.gap, "无法解读的记录"); continue }
                if let reason = f.hidden {
                    entry(.hidden, "焦点切到\(hiddenName(reason))的窗口")
                } else {
                    entry(.focus, "焦点：\(f.appName)", f.title ?? "")
                }
            case .gap:
                guard let g = try? record.decode(Gap.self) else { entry(.gap, "无法解读的记录"); continue }
                switch g.reason {
                case .blocked, .neverRead: entry(.hidden, "\(hiddenName(g.reason))的窗口", "不记录 App、标题和内容")
                default: entry(.gap, gapText(g.reason), g.appName ?? "")
                }
            case .presence:
                guard let p = try? record.decode(Presence.self) else { entry(.gap, "无法解读的记录"); continue }
                if p.state == .recordingStarted, recording {
                    // A second start without a stop in between: the app quit without saying so.
                    entry(.gap, "记录中断：App 没有正常退出", "上一条记录之后到这里没有采集", at: p.since.addingTimeInterval(-0.001))
                }
                if p.state == .recordingStarted { recording = true }
                if p.state == .recordingStopped { recording = false }
                entry(presenceStyle(p.state), presenceText(p.state), p.state == .idle ? "从最后一次输入算起" : "", at: p.since)
            case .layout:
                guard let l = try? record.decode(Layout.self) else { entry(.gap, "无法解读的记录"); continue }
                entry(.layout, "布局：\(l.screens.count) 块屏幕，\(l.windows.count) 个可见窗口", layoutText(l))
            case nil:
                entry(.gap, "未知的记录类型：\(record.kind)")
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    static func hiddenName(_ reason: Gap.Reason) -> String { reason == .blocked ? "不看名单里" : "永不读取" }

    static func gapText(_ reason: Gap.Reason) -> String {
        switch reason {
        case .noAccessibilityPermission: "没有辅助功能权限，读不到窗口"
        case .readFailed: "读取失败"
        case .unreadable: "读不到文字，OCR 也没有结果"
        case .noAccessibilityWindow: "窗口在屏幕上，但辅助功能里找不到它"
        case .blocked, .neverRead: hiddenName(reason)
        }
    }

    static func presenceStyle(_ state: Presence.State) -> TimelineEntry.Style {
        switch state {
        case .active, .awake, .unlocked, .recordingStarted: .presence
        case .idle, .asleep, .locked, .recordingStopped: .gap
        }
    }

    static func presenceText(_ state: Presence.State) -> String {
        switch state {
        case .idle: "无输入"
        case .active: "恢复输入"
        case .asleep: "睡眠，停止读取"
        case .awake: "唤醒，继续读取"
        case .locked: "锁屏，停止读取"
        case .unlocked: "解锁，继续读取"
        case .recordingStarted: "开始记录"
        case .recordingStopped: "停止记录"
        }
    }

    /// "屏幕 1：Chrome（焦点）、ChatGPT · 屏幕 2：不看"
    static func layoutText(_ layout: Layout) -> String {
        let byScreen = Dictionary(grouping: layout.windows, by: \.screen)
        return byScreen.keys.sorted().map { screen in
            let names = byScreen[screen, default: []].map { w in
                (w.hidden.map { $0 == .blocked ? "不看" : "不读" } ?? w.appName) + (w.focused ? "（焦点）" : "")
            }
            return "\(screen < 0 ? "屏幕外" : "屏幕 \(screen + 1)")：\(names.joined(separator: "、"))"
        }.joined(separator: " · ")
    }

    private static func nonEmpty(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : $0 } }
}
