import Foundation

/// The 复盘 conversation's contract with the model: the system prompt that carries the method (docs/复盘方法.md,
/// PRD §8.3) and the tagged blocks the model puts in its replies so the app can show lists, buttons and cards.
public enum ReviewPrompt {
    /// What the app sends when the user taps one of the entry buttons under the conversation.
    public enum Entry: String, CaseIterable, Sendable {
        case harvest = "谈谈今天的收获"
        case tomorrow = "安排明天"
        case mood = "今天的状态"
    }

    /// The first user message; the model answers with the 工作清单 and stops.
    public static let opening = "开始复盘。先列出今天的工作清单，然后停下来问我想先复盘哪一个。"

    public static func system(direction: String, notes: [ReviewNote], digest: String) -> String {
        let lessons = notes.filter { $0.kind == .lesson }.suffix(20).map { "- \($0.text)" }
        let selves = notes.filter { $0.kind == .selfKnowledge }.suffix(20).map { "- \($0.text)" }
        return """
        你是 Think My Day 的复盘教练。用户和你一起复盘他在电脑上的一天。你的工作是帮他看清事实、找到卡住的地方、一步步想出办法，而不是替他总结或下结论。

        # 用户
        长期方向：\(direction.isEmpty ? "（还没填）" : direction)
        他碰到抽象、没有入口的难题时，容易转去做马上能看到结果的事；问题拆成具体、可以选的小问题后，他能想得很深。他常拿别人的速度当标准，进步要和他过去的自己比。
        \(lessons.isEmpty ? "" : "以前记下的经验：\n" + lessons.joined(separator: "\n") + "\n")\(selves.isEmpty ? "" : "以前记下的自我认识：\n" + selves.joined(separator: "\n") + "\n")
        # 用词
        - 主线：用户在推进的、有名字的工作，例如「Think My Day 的构建」「XX 调研报告」。状态只有「进行中」「已完成」。刷 X、闲逛不算主线，归到「其他」。
        - 卡住的地方：球在用户手里时（AI 已经回复、在等他判断，或者本来就要他自己做的事），他停住后转去做别的事，一段时间没回来。AI 还在处理时切走是正常的并行，不算。
        - 不用「任务」「跑偏」「摸鱼」「拖延」这些词，不打分，不说教。

        # 流程（由用户主导）
        1. 用户说「开始复盘」时：只输出一句开场和下面的 <工作清单> 块，然后问一句「想先复盘哪一个？」，停下。不要分析，不要总结，不要给建议。
        2. 用户选了一条主线后，针对它：
           a. 先说卡住的地方，结构化：任务 → 出了什么问题 → 然后做了什么 → 多久回来。再问原因，给选项。
           b. 用户回答后，先说清他想解决的问题，再拆成小问题，一次只问一个，答完一个再问下一个。必要时往下再问一层，找根本原因。
           c. 结论和答案由用户自己说；你可以帮他把话说得更清楚，但不要替他想。
        3. 用户说「谈谈今天的收获」：问他今天得到了什么（做事的方法，或者关于自己的认识），帮他用自己的话说清楚。他确认后，输出 <记下> 块。
        4. 用户说「安排明天」：给几件按优先级排好的候选，让他改；他确认后，输出 <记下> 块。
        5. 用户说「今天的状态」：给几个选项；他选了或者自己说了之后，输出 <记下> 块。
        6. 任何时候用户选不了或想自己说，都尊重他。

        # 每次回复
        - 简短。一次只问一个问题。用中文。
        - 判断要有记录作依据，说到具体时间、窗口、他写的话；但不用每句都引用，可以大胆猜，猜错了他会纠正。
        - 问问题时，在回复最后附上 <选项> 块，2 到 4 个可选答案，每行一个；用户也可以不选、直接打字。
        - 不确定的事情（比如某件事算不算主线、某段时间在干什么）直接问他。

        # 格式（这些块会被程序读取，块外的文字直接显示给用户）
        <工作清单>
        {"lines":[{"title":"Think My Day 的构建","status":"进行中","result":"OCR 改为按事件触发，已合并","minutes":45}],"other":"刷 X 7 分 · 离开电脑 40 分"}
        </工作清单>

        <选项>
        不知道正确的流程
        说不清自己要什么
        </选项>

        <记下>
        {"lesson":["不熟悉的事，先问流程和每一步做完的标准"],"selfKnowledge":["碰到判断好坏的事，我容易卡住"],"tomorrow":["问 AI 一个镜头的标准制作流程","修好输入框噪音"],"mood":"推进得不错"}
        </记下>
        <记下> 里只放用户确认过的内容，没有的字段省略。tomorrow 按优先级排列。

        # 今天的记录
        \(digest)
        """
    }
}

/// One model reply, split into the prose the user reads and the blocks the app acts on.
public struct ReviewReply: Equatable, Sendable {
    public struct WorkLine: Codable, Equatable, Sendable, Identifiable {
        public var title: String
        public var status: String
        public var result: String
        public var minutes: Int?
        public var id: String { title }

        public init(title: String, status: String, result: String, minutes: Int? = nil) {
            self.title = title
            self.status = status
            self.result = result
            self.minutes = minutes
        }
    }

    public struct WorkList: Codable, Equatable, Sendable {
        public var lines: [WorkLine]
        public var other: String?

        public init(lines: [WorkLine], other: String? = nil) {
            self.lines = lines
            self.other = other
        }
    }

    /// What the user confirmed and the app may save.
    public struct Keep: Codable, Equatable, Sendable {
        public var lesson: [String]?
        public var selfKnowledge: [String]?
        public var tomorrow: [String]?
        public var mood: String?

        public init(lesson: [String]? = nil, selfKnowledge: [String]? = nil, tomorrow: [String]? = nil, mood: String? = nil) {
            self.lesson = lesson
            self.selfKnowledge = selfKnowledge
            self.tomorrow = tomorrow
            self.mood = mood
        }

        public var isEmpty: Bool { notes(dayID: UUID(), at: Date()).isEmpty }

        /// The notes to store, about `dayID`.
        public func notes(dayID: UUID, at: Date) -> [ReviewNote] {
            func clean(_ s: [String]?) -> [String] {
                (s ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            var out = clean(lesson).map { ReviewNote(dayID: dayID, at: at, kind: .lesson, text: $0) }
            out += clean(selfKnowledge).map { ReviewNote(dayID: dayID, at: at, kind: .selfKnowledge, text: $0) }
            out += clean(tomorrow).enumerated().map { ReviewNote(dayID: dayID, at: at, kind: .tomorrow, text: $1, rank: $0 + 1) }
            out += clean(mood.map { [$0] }).map { ReviewNote(dayID: dayID, at: at, kind: .mood, text: $0) }
            return out
        }
    }

    public var text: String
    public var workList: WorkList?
    public var options: [String]
    public var keep: Keep?

    public init(text: String, workList: WorkList? = nil, options: [String] = [], keep: Keep? = nil) {
        self.text = text
        self.workList = workList
        self.options = options
        self.keep = keep
    }

    public static func parse(_ raw: String) -> ReviewReply {
        var text = raw
        let workList = take("工作清单", from: &text).flatMap { decode(WorkList.self, $0) }
        let options = take("选项", from: &text).map { block in
            block.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^([-*•]|\d+[.、)])\s*"#, with: "", options: .regularExpression) }
                .filter { !$0.isEmpty }
        } ?? []
        let keep = take("记下", from: &text).flatMap { decode(Keep.self, $0) }
        let prose = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewReply(text: prose, workList: workList, options: options, keep: keep)
    }

    /// Removes `<tag>…</tag>` from `text` and returns what was inside; a block the model left open runs to the end.
    private static func take(_ tag: String, from text: inout String) -> String? {
        guard let open = text.range(of: "<\(tag)>") else { return nil }
        let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex)
        let inner = String(text[open.upperBound..<(close?.lowerBound ?? text.endIndex)])
        text.removeSubrange(open.lowerBound..<(close?.upperBound ?? text.endIndex))
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// JSON, tolerating a ```json fence around it.
    private static func decode<T: Decodable>(_ type: T.Type, _ block: String) -> T? {
        var s = block
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") { s = String(s[start...end]) }
        return try? JSONDecoder().decode(type, from: Data(s.utf8))
    }
}
