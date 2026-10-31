import AppKit
import SwiftUI
import ThinkMyDayCore

/// 原始时间线: the records of one 复盘日 in time order, without any AI summary (PRD §7, FR-17).
@MainActor
final class TimelineModel: ObservableObject {
    @Published private(set) var days: [ReviewDay] = []
    @Published var selectedDay: UUID? { didSet { if selectedDay != oldValue { Task { await loadEntries() } } } }
    @Published private(set) var entries: [TimelineEntry] = []
    @Published private(set) var error: String?
    @Published var showLayout = false

    private let store: RecordStore

    init(store: RecordStore) { self.store = store }

    func reload() async {
        do {
            days = try await store.days().reversed()
            if selectedDay == nil || !days.contains(where: { $0.id == selectedDay }) {
                selectedDay = days.first?.id
            } else {
                await loadEntries()
            }
        } catch {
            self.error = AppDelegate.describe(error)
        }
    }

    private func loadEntries() async {
        guard let selectedDay else { return entries = [] }
        do {
            entries = Timeline.entries(try await store.records(dayID: selectedDay))
            error = nil
        } catch {
            entries = []
            self.error = AppDelegate.describe(error)
        }
    }

    var day: ReviewDay? { days.first { $0.id == selectedDay } }
    var visibleEntries: [TimelineEntry] { showLayout ? entries : entries.filter { $0.style != .layout } }
}

struct TimelineView: View {
    @ObservedObject var model: TimelineModel

    var body: some View {
        NavigationSplitView {
            List(model.days, id: \.id, selection: $model.selectedDay) { day in
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.startedAt.formatted(.dateTime.month().day().weekday()))
                    Text(Self.range(day)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                if let error = model.error {
                    ContentUnavailableView("打不开记录", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if model.visibleEntries.isEmpty {
                    ContentUnavailableView("这一天还没有记录", systemImage: "clock")
                } else {
                    List(model.visibleEntries) { TimelineRow(entry: $0) }
                        .listStyle(.inset)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $model.showLayout) { Label("显示布局", systemImage: "rectangle.split.2x1") }
                    .help("显示桌面布局的变化")
            }
            ToolbarItem {
                Button { Task { await model.reload() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
            }
        }
        .task { await model.reload() }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder private var header: some View {
        if let day = model.day {
            HStack(alignment: .firstTextBaseline) {
                Text(day.startedAt.formatted(.dateTime.year().month().day().weekday(.wide))).font(.headline)
                Text(Self.range(day)).foregroundStyle(.secondary)
                if let planned = day.plannedStart {
                    Text(PlanComparison.text(start: day.startedAt, planned: planned)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.entries.count) 条记录").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    static func range(_ day: ReviewDay) -> String {
        let start = day.startedAt.formatted(date: .omitted, time: .shortened)
        guard let end = day.endedAt else { return "\(start) 开启 · 记录中" }
        return "\(start)–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry
    @State private var expanded = false
    private static let collapsedLines = 6

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Image(systemName: icon).foregroundStyle(tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.headline).fontWeight(entry.style == .content ? .semibold : .regular).foregroundStyle(entry.style == .hidden ? .secondary : .primary)
                if !entry.detail.isEmpty {
                    Text(entry.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
                if !entry.lines.isEmpty {
                    let shown = expanded ? entry.lines : Array(entry.lines.prefix(Self.collapsedLines))
                    Text(shown.joined(separator: "\n")).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if entry.lines.count > Self.collapsedLines {
                        Button(expanded ? "收起" : "展开全部 \(entry.lines.count) 行") { expanded.toggle() }.buttonStyle(.link).font(.callout)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .listRowBackground(entry.style == .gap ? Color.orange.opacity(0.08) : Color.clear)
    }

    private var icon: String {
        switch entry.style {
        case .content: "text.alignleft"
        case .focus: "macwindow"
        case .layout: "rectangle.split.2x1"
        case .gap: "exclamationmark.circle"
        case .hidden: "eye.slash"
        case .presence: "circle.dashed"
        }
    }

    private var tint: Color {
        switch entry.style {
        case .gap: .orange
        case .hidden, .presence, .layout: .secondary
        case .content, .focus: .accentColor
        }
    }
}

/// Owns the timeline window; reopening brings the same window forward.
@MainActor
final class TimelineWindowController {
    private var window: NSWindow?
    private var model: TimelineModel?

    func show(store: RecordStore) {
        if let window, let model {
            Task { await model.reload() }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = TimelineModel(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "原始时间线"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: TimelineView(model: model))
        window.setFrameAutosaveName("TimelineWindow")
        window.center()
        self.window = window
        self.model = model
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
