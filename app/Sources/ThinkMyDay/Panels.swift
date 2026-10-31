import AppKit
import SwiftUI
import ThinkMyDayCore

/// Hosts a SwiftUI view in a small floating panel that comes to the front even though the app has no Dock icon.
@MainActor
final class PanelPresenter {
    private var panel: NSPanel?

    func show<Content: View>(title: String, @ViewBuilder content: (_ close: @escaping () -> Void) -> Content) {
        close()
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentViewController = NSHostingController(rootView: content { [weak self] in self?.close() })
        panel.center()
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

// MARK: - 开启一天

struct StartDayView: View {
    let plannedStart: PlannedStart?
    /// A day the user forgot to end; starting closes it.
    let unfinished: ReviewDay?
    let start: () async throws -> ReviewDay
    let close: () -> Void

    @State private var started: ReviewDay?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let started {
                Text("已开启，开始记录").font(.headline)
                if let planned = started.plannedStart {
                    Text(PlanComparison.text(start: started.startedAt, planned: planned)).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("好", action: close).keyboardShortcut(.defaultAction)
                }
            } else {
                Text("开启一天").font(.headline)
                if let plannedStart {
                    Text("计划 \(plannedStart.clockText) 开始").foregroundStyle(.secondary)
                }
                section("待办", "待办区在之后的版本加入。")
                section("不看名单", "不看名单在之后的版本加入。")
                if let unfinished {
                    Text("上一个复盘日（\(unfinished.startedAt.formatted(date: .abbreviated, time: .shortened)) 开启）还没结束，开启后它会在此刻结束。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("取消", action: close).keyboardShortcut(.cancelAction)
                    Button("开启一天！") {
                        working = true
                        Task {
                            do { started = try await start() } catch { self.error = "开启失败：\(error)" }
                            working = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func section(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 计划开始时刻

struct PlannedStartView: View {
    let save: (PlannedStart) -> Void
    let close: () -> Void

    @State private var time: Date
    @State private var zoneID: String

    init(current: PlannedStart?, save: @escaping (PlannedStart) -> Void, close: @escaping () -> Void) {
        self.save = save
        self.close = close
        let plan = current ?? PlannedStart(hour: 9, minute: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = plan.timeZone
        _time = State(initialValue: calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: Date()) ?? Date())
        _zoneID = State(initialValue: plan.timeZoneID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("你的一天一般从几点开始？").font(.headline)
            Text("开启一天时，会和这个时刻对照，告诉你今天开始得早了还是晚了。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                DatePicker("开始时刻", selection: $time, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, TimeZone(identifier: zoneID) ?? .current)
                Picker("时区", selection: $zoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
            }
            HStack {
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button("保存") {
                    let zone = TimeZone(identifier: zoneID) ?? .current
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = zone
                    let parts = calendar.dateComponents([.hour, .minute], from: time)
                    save(PlannedStart(hour: parts.hour ?? 9, minute: parts.minute ?? 0, timeZone: zone))
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
