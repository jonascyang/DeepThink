import Foundation

/// One 复盘日's records condensed into text a model can read in one request: what was in focus and when,
/// what the user sent, what new text appeared, presence edges, and per-window activity in short blocks.
/// Facts only; working out 事情, 主线 and 逃开 is the model's job.
public enum DayDigest {
    public struct Limits: Sendable {
        /// Whole digest.
        public var totalChars = 60_000
        /// New text kept from one window (same app and title) over the day.
        public var perWindowChars = 4_000
        /// One line of window text.
        public var lineChars = 160
        /// Activity is summed over blocks of this length.
        public var activityBlock: TimeInterval = 600

        public init() {}
    }

    public static func make(day: ReviewDay, records: [Record], timeZone: TimeZone = .current, limits: Limits = Limits()) -> String {
        let records = records.sorted { $0.at < $1.at }
        let clock = Clock(timeZone)
        var out: [String] = []
        let end = day.endedAt.map(clock.text) ?? "还在记录"
        out.append("复盘日：\(clock.date(day.startedAt)) \(clock.text(day.startedAt))–\(end)")

        let totals = focusTotals(records)
        if !totals.isEmpty {
            out.append("\n## 焦点时长合计（按 App；同时可见的窗口不重复计）")
            out += totals
        }

        out.append("\n## 时间线（焦点切换、无输入、锁屏、睡眠）")
        var lastFocus = ""
        for r in records {
            switch RecordKind(rawValue: r.kind) {
            case .focus:
                guard let f = try? r.decode(Focus.self) else { continue }
                let line = f.hidden != nil ? "不看名单或不读取的窗口：\(f.appName)" : "\(f.appName)「\(short(f.title))」"
                if line != lastFocus { out.append("\(clock.text(r.at)) 焦点 \(line)"); lastFocus = line }
            case .presence:
                guard let p = try? r.decode(Presence.self) else { continue }
                out.append("\(clock.text(p.since)) \(presenceText(p.state))")
            default: continue
            }
        }

        let sent = records.compactMap { r -> String? in
            guard RecordKind(rawValue: r.kind) == .sent, let s = try? r.decode(SentText.self) else { return nil }
            return "\(clock.text(r.at)) \(s.appName)「\(s.title ?? "")」：\(s.text)"
        }
        if !sent.isEmpty {
            out.append("\n## 用户自己发出的话（确定是用户写的）")
            out += sent
        }

        out.append("\n## 各窗口新出现的文字（节选，同一窗口按时间排列）")
        var used: [String: Int] = [:]
        var order: [String] = []
        var blocks: [String: [String]] = [:]
        for r in records where RecordKind(rawValue: r.kind) == .windowText {
            guard let t = try? r.decode(WindowText.self), !t.added.isEmpty else { continue }
            let key = "\(t.appName)「\(short(t.title))」\(t.url.map { " \($0)" } ?? "")"
            if blocks[key] == nil { order.append(key); blocks[key] = [] }
            var budget = limits.perWindowChars - used[key, default: 0]
            guard budget > 0 else { continue }
            var lines: [String] = []
            for line in t.added {
                let cut = line.count > limits.lineChars ? String(line.prefix(limits.lineChars)) + "…" : line
                if cut.count > budget { break }
                budget -= cut.count
                lines.append(cut)
            }
            used[key] = limits.perWindowChars - budget
            if !lines.isEmpty {
                blocks[key]?.append("\(clock.text(r.at))\(t.focused ? " 焦点" : "")\(t.method == .ocr ? " OCR" : "")：\(lines.joined(separator: " / "))")
            }
        }
        for key in order where !(blocks[key]?.isEmpty ?? true) {
            out.append("### \(key)")
            out += blocks[key] ?? []
        }

        let activity = activityLines(records, clock: clock, block: limits.activityBlock)
        if !activity.isEmpty {
            out.append("\n## 操作统计（每 \(Int(limits.activityBlock / 60)) 分钟，按窗口；字数来自输入框长度，不读按键）")
            out += activity
        }

        var text = out.joined(separator: "\n")
        if text.count > limits.totalChars {
            text = String(text.prefix(limits.totalChars)) + "\n……（后面的记录太长，省略了）"
        }
        return text
    }

    /// Window titles can be whole tweets; the timeline only needs enough to tell windows apart.
    static func short(_ title: String?, _ limit: Int = 60) -> String {
        guard let title else { return "" }
        return title.count > limit ? String(title.prefix(limit)) + "…" : title
    }

    private static func focusTotals(_ records: [Record]) -> [String] {
        var seconds: [String: Int] = [:]
        for r in records where RecordKind(rawValue: r.kind) == .activity {
            guard let a = try? r.decode(Activity.self), a.focusedSeconds > 0 else { continue }
            seconds[a.appName, default: 0] += a.focusedSeconds
        }
        return seconds.filter { $0.value >= 60 }.sorted { $0.value > $1.value }.map { "\($0.key)：\($0.value / 60) 分" }
    }

    static func presenceText(_ state: Presence.State) -> String {
        switch state {
        case .idle: "开始无输入"
        case .active: "恢复输入"
        case .asleep: "睡眠"
        case .awake: "唤醒"
        case .locked: "锁屏"
        case .unlocked: "解锁"
        case .recordingStarted: "开始记录"
        case .recordingStopped: "停止记录"
        }
    }

    private static func activityLines(_ records: [Record], clock: Clock, block: TimeInterval) -> [String] {
        struct Sum { var focused = 0, typed = 0, added = 0, scroll = 0, clicks = 0, still = 0 }
        var sums: [Int: [String: Sum]] = [:]
        for r in records where RecordKind(rawValue: r.kind) == .activity {
            guard let a = try? r.decode(Activity.self) else { continue }
            let slot = Int(a.from.timeIntervalSince1970 / block)
            var s = sums[slot, default: [:]][a.appName, default: Sum()]
            s.focused += a.focusedSeconds; s.typed += a.typedChars; s.added += a.contentAddedChars
            s.scroll += a.scrollSeconds; s.clicks += a.clicks; s.still += a.stillSeconds
            sums[slot, default: [:]][a.appName] = s
        }
        return sums.keys.sorted().flatMap { slot -> [String] in
            let start = Date(timeIntervalSince1970: Double(slot) * block)
            return (sums[slot] ?? [:]).sorted { $0.value.focused > $1.value.focused }.compactMap { app, s in
                guard s.focused > 0 || s.typed > 0 || s.added > 0 else { return nil }
                var parts = ["焦点 \(s.focused / 60) 分"]
                if s.typed > 0 { parts.append("输入 \(s.typed) 字") }
                if s.added > 0 { parts.append("新内容 \(s.added) 字") }
                if s.scroll > 0 { parts.append("滚动 \(s.scroll) 秒") }
                if s.still > 0 { parts.append("没有操作 \(s.still) 秒") }
                return "\(clock.text(start)) \(app)：\(parts.joined(separator: "，"))"
            }
        }
    }

    struct Clock {
        let calendar: Calendar
        init(_ zone: TimeZone) {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = zone
            calendar = c
        }
        func text(_ date: Date) -> String {
            let p = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", p.hour ?? 0, p.minute ?? 0)
        }
        func date(_ date: Date) -> String {
            let p = calendar.dateComponents([.month, .day], from: date)
            return "\(p.month ?? 0) 月 \(p.day ?? 0) 日"
        }
    }
}
