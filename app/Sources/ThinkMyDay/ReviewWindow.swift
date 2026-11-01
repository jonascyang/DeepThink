import AppKit
import SwiftUI
import ThinkMyDayCore

/// 复盘 (PRD §8.3): the model lists today's 主线 and stops; the user picks one to look at, or taps an entry
/// for 收获, tomorrow or today's mood. Only what the user confirms in a <记下> card is stored.
@MainActor
final class ReviewModel: ObservableObject {
    struct Item: Identifiable {
        enum Role { case coach, me }
        let id = UUID()
        let role: Role
        let text: String
        var reply: ReviewReply?
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var saved: Set<UUID> = []
    @Published private(set) var dismissed: Set<UUID> = []
    @Published var draft = ""

    let day: ReviewDay
    private let store: RecordStore
    private var history: [ChatMessage] = []

    init(store: RecordStore, day: ReviewDay) {
        self.store = store
        self.day = day
    }

    var title: String { "复盘 · \(day.startedAt.formatted(.dateTime.month().day().weekday()))" }

    /// The latest coach reply; only its options are offered as buttons.
    var lastCoachID: UUID? { items.last(where: { $0.role == .coach })?.id }

    func start() async {
        items = []
        saved = []
        dismissed = []
        error = nil
        busy = true
        defer { busy = false }
        do {
            let records = try await store.records(dayID: day.id)
            let digest = DayDigest.make(day: day, records: records)
            let notes = try await store.notes()
            history = [ChatMessage(.system, ReviewPrompt.system(direction: Settings.direction, notes: notes, digest: digest))]
            try await ask(ReviewPrompt.opening, show: false)
        } catch {
            self.error = Self.describe(error)
        }
    }

    func send(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, history.first != nil else { return }
        draft = ""
        busy = true
        error = nil
        defer { busy = false }
        do { try await ask(text, show: true) } catch { self.error = Self.describe(error) }
    }

    private func ask(_ text: String, show: Bool) async throws {
        if show { items.append(Item(role: .me, text: text)) }
        history.append(ChatMessage(.user, text))
        do {
            let raw = try await Settings.reviewModel.reply(to: history)
            history.append(ChatMessage(.assistant, raw))
            let reply = ReviewReply.parse(raw)
            items.append(Item(role: .coach, text: reply.text, reply: reply))
        } catch {
            // Let the user send the same thing again.
            history.removeLast()
            if show { items.removeLast(); draft = text }
            throw error
        }
    }

    func keep(_ item: Item) async {
        guard let keep = item.reply?.keep else { return }
        do {
            try await store.append(keep.notes(dayID: day.id, at: Date()).map(Event.reviewNoted))
            saved.insert(item.id)
        } catch {
            self.error = "没有记下来：\(Self.describe(error))"
        }
    }

    func dismiss(_ item: Item) { dismissed.insert(item.id) }

    static func describe(_ error: Error) -> String {
        if let e = error as? ChatModelError { return e.description }
        return AppDelegate.describe(error)
    }
}

struct ReviewView: View {
    @ObservedObject var model: ReviewModel
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.title).font(.title3.weight(.semibold))
                Spacer()
                Button("重新开始") { Task { await model.start() } }.disabled(model.busy)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.items) { item in
                            row(item).id(item.id)
                        }
                        if model.busy {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在看你的记录…").foregroundStyle(.secondary) }
                                .id("busy")
                        }
                        if let error = model.error {
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: model.items.count) { proxy.scrollTo(model.items.last?.id, anchor: .bottom) }
                .onChange(of: model.busy) { if model.busy { proxy.scrollTo("busy", anchor: .bottom) } }
            }
            Divider()
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(ReviewPrompt.Entry.allCases, id: \.self) { entry in
                        Button(entry.rawValue) { Task { await model.send(entry.rawValue) } }
                            .buttonStyle(.bordered).disabled(model.busy || model.items.isEmpty)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    TextField("用自己的话回答，或者随便问", text: $model.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...5).focused($typing)
                        .onSubmit { Task { await model.send(model.draft) } }
                    Button("发送") { Task { await model.send(model.draft) } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.busy || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    @ViewBuilder private func row(_ item: ReviewModel.Item) -> some View {
        switch item.role {
        case .me:
            HStack {
                Spacer(minLength: 80)
                Text(item.text).padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .textSelection(.enabled)
            }
        case .coach:
            VStack(alignment: .leading, spacing: 12) {
                if !item.text.isEmpty {
                    Text((try? AttributedString(markdown: item.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(item.text))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if let list = item.reply?.workList { workList(list, live: item.id == model.lastCoachID) }
                if let keep = item.reply?.keep, !keep.isEmpty, !model.dismissed.contains(item.id) { keepCard(keep, item) }
                if item.id == model.lastCoachID, let options = item.reply?.options, !options.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(options, id: \.self) { option in
                            Button { Task { await model.send(option) } } label: {
                                Text(option).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered).controlSize(.large).disabled(model.busy)
                        }
                        Button("我自己说") { typing = true }.buttonStyle(.link)
                    }
                }
            }
        }
    }

    private func workList(_ list: ReviewReply.WorkList, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(list.lines) { line in
                Button { Task { await model.send("我想复盘：\(line.title)") } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.title).font(.headline)
                            Text(line.status).font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background((line.status == "已完成" ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                            Spacer()
                            if let minutes = line.minutes { Text("\(minutes) 分").monospacedDigit().foregroundStyle(.secondary) }
                        }
                        Text(line.result).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).disabled(!live || model.busy)
            }
            if let other = list.other, !other.isEmpty {
                Text("其他：\(other)").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func keepCard(_ keep: ReviewReply.Keep, _ item: ReviewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("要记下这些吗？").font(.subheadline.weight(.semibold))
            ForEach(keep.notes(dayID: model.day.id, at: Date())) { note in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Self.label(note)).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    Text(note.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.saved.contains(item.id) {
                Label("已记下", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                HStack {
                    Button("记下") { Task { await model.keep(item) } }.buttonStyle(.borderedProminent)
                    Button("不用") { model.dismiss(item) }
                }
            }
        }
        .padding(14)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    static func label(_ note: ReviewNote) -> String {
        switch note.kind {
        case .lesson: "经验"
        case .selfKnowledge: "自我认识"
        case .tomorrow: "明天 \(note.rank ?? 0)"
        case .mood: "状态"
        }
    }
}

@MainActor
final class ReviewWindowController {
    private var window: NSWindow?
    private var model: ReviewModel?

    func show(store: RecordStore, day: ReviewDay) {
        if let window, let model, model.day.id == day.id {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = ReviewModel(store: store, day: day)
        let window = window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                                        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "复盘"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ReviewView(model: model))
        window.setContentSize(NSSize(width: 760, height: 720))
        window.center()
        self.window = window
        self.model = model
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await model.start() }
    }
}

// MARK: - 复盘模型

struct ReviewModelSettingsView: View {
    let close: () -> Void
    @State private var baseURL = Settings.reviewBaseURL
    @State private var modelName = Settings.reviewModelName
    @State private var direction = Settings.direction
    @State private var testing = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("复盘用的模型").font(.headline)
            Text("兼容 OpenAI 格式的地址。用 magpie 时填它的本机地址；复盘时，当天的记录会发到这里。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("地址", text: $baseURL)
                TextField("模型", text: $modelName)
                TextField("长期方向", text: $direction, axis: .vertical).lineLimit(2...4)
            }
            if let result { Text(result).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("测试连接") {
                    testing = true
                    result = nil
                    let model = OpenAICompatibleModel(baseURL: baseURL, model: modelName, timeout: 60)
                    Task {
                        do { result = "能用：\(try await model.reply(to: [ChatMessage(.user, "只回复两个字：你好")]))" }
                        catch { result = ReviewModel.describe(error) }
                        testing = false
                    }
                }
                .disabled(testing)
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button("保存") {
                    Settings.reviewBaseURL = baseURL
                    Settings.reviewModelName = modelName
                    Settings.direction = direction
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
