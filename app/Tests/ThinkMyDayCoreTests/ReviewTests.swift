import Foundation
import Testing
@testable import ThinkMyDayCore

@Suite struct ReviewReplyTests {
    @Test func splitsProseFromBlocks() {
        let raw = """
        今天你推进了两条主线。

        <工作清单>
        ```json
        {"lines":[{"title":"Think My Day 的构建","status":"进行中","result":"OCR 改为按事件触发，已合并","minutes":45},
                  {"title":"《抵达之后》的制作","status":"进行中","result":"场景改成 9 处","minutes":13}],
         "other":"刷 X 7 分"}
        ```
        </工作清单>

        想先复盘哪一个？
        """
        let r = ReviewReply.parse(raw)
        #expect(r.text == "今天你推进了两条主线。\n\n想先复盘哪一个？")
        #expect(r.workList?.lines.map(\.title) == ["Think My Day 的构建", "《抵达之后》的制作"])
        #expect(r.workList?.lines.first?.minutes == 45)
        #expect(r.workList?.other == "刷 X 7 分")
        #expect(r.options.isEmpty && r.keep == nil)
    }

    @Test func readsOptionsEvenWithBulletsOrAnOpenBlock() {
        let r = ReviewReply.parse("你觉得卡在哪里？\n<选项>\n- 不知道正确的流程\n2. 说不清自己要什么\n在等结构完美")
        #expect(r.text == "你觉得卡在哪里？")
        #expect(r.options == ["不知道正确的流程", "说不清自己要什么", "在等结构完美"])
    }

    @Test func keepBecomesNotesInOrder() {
        let r = ReviewReply.parse("""
        好，记下了。
        <记下>
        {"lesson":["先问流程"],"tomorrow":["问一个镜头的标准流程","  ","修输入框噪音"],"mood":"推进得不错"}
        </记下>
        """)
        let day = UUID(), at = Date(timeIntervalSince1970: 0)
        let notes = r.keep?.notes(dayID: day, at: at) ?? []
        #expect(notes.map(\.kind) == [.lesson, .tomorrow, .tomorrow, .mood])
        #expect(notes.filter { $0.kind == .tomorrow }.map(\.rank) == [1, 2])
        #expect(notes.map(\.text) == ["先问流程", "问一个镜头的标准流程", "修输入框噪音", "推进得不错"])
    }

    @Test func badJSONIsDroppedNotShown() {
        let r = ReviewReply.parse("看看这个\n<工作清单>\n{坏掉的 json\n</工作清单>")
        #expect(r.text == "看看这个")
        #expect(r.workList == nil)
    }

    @Test func promptCarriesDirectionNotesAndRecords() {
        let day = UUID()
        let notes = [ReviewNote(dayID: day, at: Date(), kind: .lesson, text: "先问流程"),
                     ReviewNote(dayID: day, at: Date(), kind: .selfKnowledge, text: "判断类的事容易卡住")]
        let s = ReviewPrompt.system(direction: "想清楚；稳住几条主线", notes: notes, digest: "复盘日：10 月 31 日")
        #expect(s.contains("想清楚；稳住几条主线") && s.contains("先问流程") && s.contains("判断类的事容易卡住") && s.contains("复盘日：10 月 31 日"))
    }
}

@Suite struct DayDigestTests {
    let day = ReviewDay(startedAt: Date(timeIntervalSince1970: 1_793_448_000), endedAt: Date(timeIntervalSince1970: 1_793_452_800))
    let utc8 = TimeZone(secondsFromGMT: 8 * 3600)!

    private func rec<T: Encodable>(_ seconds: Double, _ kind: RecordKind, _ body: T) throws -> Record {
        try Record(dayID: day.id, at: day.startedAt.addingTimeInterval(seconds), kind: kind, body: body)
    }

    @Test func listsFocusSentTextNewTextAndActivity() throws {
        let records = [
            try rec(0, .focus, Focus(windowID: 1, bundleID: "com.openai.chat", appName: "ChatGPT", title: "制片团队搭建")),
            try rec(30, .windowText, WindowText(windowID: 1, bundleID: "com.openai.chat", appName: "ChatGPT", title: "制片团队搭建", focused: true,
                                               method: .accessibility, added: ["回复已完成：62 镜"], lineCount: 3, visibleChars: 50, truncated: false)),
            try rec(60, .sent, SentText(windowID: 1, bundleID: "com.openai.chat", appName: "ChatGPT", title: "制片团队搭建", text: "这个页面的布局我很不喜欢")),
            try rec(120, .presence, Presence(state: .locked, since: day.startedAt.addingTimeInterval(120))),
            try rec(0, .activity, {
                var a = Activity(windowID: 1, bundleID: "com.openai.chat", appName: "ChatGPT", place: nil,
                                 from: day.startedAt, to: day.startedAt.addingTimeInterval(60))
                a.focusedSeconds = 60; a.typedChars = 12
                return a
            }()),
        ]
        let text = DayDigest.make(day: day, records: records, timeZone: utc8)
        #expect(text.contains("ChatGPT「制片团队搭建」"))
        #expect(text.contains("这个页面的布局我很不喜欢"))
        #expect(text.contains("回复已完成：62 镜"))
        #expect(text.contains("锁屏"))
        #expect(text.contains("输入 12 字"))
    }

    @Test func staysWithinItsBudget() throws {
        let long = String(repeating: "很长的一行字", count: 50)
        var records: [Record] = []
        for i in 0..<400 {
            records.append(try rec(Double(i), .windowText, WindowText(windowID: UInt32(i % 7), bundleID: "b", appName: "App\(i % 7)", title: "t",
                                                                     focused: false, method: .accessibility, added: [long, "\(i)"],
                                                                     lineCount: 2, visibleChars: 10, truncated: false)))
        }
        var limits = DayDigest.Limits()
        limits.totalChars = 5_000
        let text = DayDigest.make(day: day, records: records, timeZone: utc8, limits: limits)
        #expect(text.count <= 5_000 + 40)
        #expect(!text.contains(long))
    }
}

@Suite struct ChatModelTests {
    @Test func rejectsAddressesThatAreNotHTTP() async {
        let model = OpenAICompatibleModel(baseURL: "magpie", model: "m")
        await #expect(throws: ChatModelError.badURL("magpie")) { try await model.reply(to: [ChatMessage(.user, "hi")]) }
    }
}
