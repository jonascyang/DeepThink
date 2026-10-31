import AppKit
import SwiftUI
import ThinkMyDayCore

/// The 不看名单 shared by the menu, the 开启一天 panel and the capturer. Edits apply to the next sample.
@MainActor
final class BlockListModel: ObservableObject {
    @Published private(set) var list: BlockList
    private let onChange: (BlockList) -> Void

    init(list: BlockList, onChange: @escaping (BlockList) -> Void) {
        self.list = list
        self.onChange = onChange
    }

    func add(_ app: BlockList.App) { update { $0.add(app) } }
    func remove(_ bundleID: String) { update { $0.remove(bundleID) } }

    private func update(_ change: (inout BlockList) -> Void) {
        change(&list)
        onChange(list)
    }

    var summary: String {
        let names = list.apps.map(\.name)
        if names.isEmpty { return "空" }
        return names.prefix(4).joined(separator: "、") + (names.count > 4 ? " 等 \(names.count) 个" : "")
    }

    /// Apps with a Dock icon that are running and not on the list.
    var runningCandidates: [BlockList.App] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { BlockList.App(bundleID: $0, name: app.localizedName ?? $0) } }
            .filter { !list.contains($0.bundleID) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Lets the user pick an app from /Applications.
    func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "选择不想被记录的 App"
        panel.prompt = "加入不看名单"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] ?? bundle.infoDictionary?["CFBundleName"]) as? String
            add(BlockList.App(bundleID: id, name: name ?? url.deletingPathExtension().lastPathComponent))
        }
    }
}

struct BlockListView: View {
    @ObservedObject var model: BlockListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("名单里的 App 不记录内容和标题，只在时间线上留「不看」的时段。无痕窗口、浏览器里的钱包和密码管理器插件、密码输入框永远不读，不在名单里。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(model.list.apps, id: \.bundleID) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: Self.icon(for: app.bundleID)).resizable().frame(width: 18, height: 18)
                        Text(app.name)
                        Spacer()
                        Button {
                            model.remove(app.bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移出不看名单")
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 220)
            HStack {
                Button("添加 App…") { model.chooseApp() }
                Menu("从正在运行的 App 添加") {
                    ForEach(model.runningCandidates, id: \.bundleID) { app in
                        Button(app.name) { model.add(app) }
                    }
                }
                .fixedSize()
            }
        }
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}

/// The editor on its own, opened from the menu.
struct BlockListPanel: View {
    @ObservedObject var model: BlockListModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            BlockListView(model: model)
            Button("完成", action: close).keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 420)
    }
}
