import Foundation

/// Turns records.jsonl into a Markdown report. Only aggregate numbers appear in the report.
enum Report {
    static func generate() -> URL {
        let lines = RecordStore.shared.readAll()
        let dec = JSONDecoder()
        var samples: [SampleRec] = [], launches: [LaunchRec] = [], flags: [FlagRec] = [], ocrs: [OCRRec] = []
        var chromes: [ChromeRec] = [], histories: [HistoryRec] = [], resources: [ResourceRec] = []
        for line in lines {
            guard let k = try? dec.decode(KindOnly.self, from: line) else { continue }
            switch k.kind {
            case "sample": if let r = try? dec.decode(SampleRec.self, from: line) { samples.append(r) }
            case "launch": if let r = try? dec.decode(LaunchRec.self, from: line) { launches.append(r) }
            case "flag": if let r = try? dec.decode(FlagRec.self, from: line) { flags.append(r) }
            case "ocr": if let r = try? dec.decode(OCRRec.self, from: line) { ocrs.append(r) }
            case "chrome": if let r = try? dec.decode(ChromeRec.self, from: line) { chromes.append(r) }
            case "history": if let r = try? dec.decode(HistoryRec.self, from: line) { histories.append(r) }
            case "resource": if let r = try? dec.decode(ResourceRec.self, from: line) { resources.append(r) }
            default: break
            }
        }

        var md = "# M0b 探测报告（自动生成）\n\n"
        md += "生成时间：\(fmtDate(Date().timeIntervalSince1970))。本报告只含统计数字，不含屏幕文字、窗口标题或网址。\n\n"

        // Run overview
        let hours = activeHours(samples)
        md += "## 运行概况\n\n"
        md += "| 项 | 值 |\n| --- | --- |\n"
        md += "| 采样次数 | \(samples.count) |\n"
        if let first = samples.first, let last = samples.last {
            md += "| 时间范围 | \(fmtDate(first.ts)) — \(fmtDate(last.ts)) |\n"
        }
        md += "| 有效运行时长（采样间隔 ≤ 2 分钟的累计） | \(String(format: "%.2f", hours)) 小时 |\n"
        let sampleMs = samples.map(\.ms)
        md += "| 单次采样耗时 中位 / p95 / 最大 | \(f(pct(sampleMs, 50))) / \(f(pct(sampleMs, 95))) / \(f(sampleMs.max() ?? 0)) ms |\n"
        md += "| 无辅助功能权限的采样 | \(samples.filter { !$0.axTrusted }.count) |\n\n"

        // Launches / permission retention
        md += "## 启动与授权保留\n\n"
        md += "每次启动记录一行。重新构建、重新安装后若「辅助功能」仍为是，说明授权被保留。\n\n"
        md += "| 启动时间 | 版本 | 辅助功能 | 屏幕录制 | 签名证书 | cdhash | 指定要求（DR） |\n| --- | --- | --- | --- | --- | --- | --- |\n"
        for l in launches {
            md += "| \(fmtDate(l.ts)) | \(l.version) (\(l.build)) | \(yn(l.axTrusted)) | \(yn(l.screenCaptureGranted)) | \(l.signingCertificate ?? "?") | \(String((l.cdhash ?? "?").prefix(12))) | `\(l.designatedRequirement ?? "?")` |\n"
        }
        md += "\n"

        // Per app
        let allObs = samples.flatMap(\.windows)
        let byApp = Dictionary(grouping: allObs, by: \.bundleId)
        md += "## 各 App 可读性\n\n"
        md += "「不可读」= 匹配到辅助功能窗口、但可见字数 < 50。字数为单个窗口单次采样的可见字数。\n\n"
        md += "| App | 窗口观测数 | 焦点占比 | 可见字数 中位 | 不可读比例 | AX 未匹配 | 读取耗时 中位 / p95 (ms) | 截断 | 跳过原因 |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n"
        for (bundle, obs) in byApp.sorted(by: { $0.value.count > $1.value.count }) {
            let read = obs.filter { $0.skipped == nil }
            let matched = read.filter(\.axMatched)
            let unreadable = matched.filter { $0.axVisibleChars < 50 }.count
            let skipped = Set(obs.compactMap(\.skipped)).sorted().joined(separator: ", ")
            md += "| \(obs.first?.app ?? bundle) `\(bundle)` | \(obs.count) | \(p(obs.filter(\.focused).count, obs.count)) | \(Int(pct(matched.map { Double($0.axVisibleChars) }, 50))) | \(p(unreadable, matched.count)) | \(p(read.count - matched.count, read.count)) | \(f(pct(matched.map(\.axMs), 50))) / \(f(pct(matched.map(\.axMs), 95))) | \(p(matched.filter(\.truncated).count, matched.count)) | \(skipped) |\n"
        }
        md += "\n"

        // Electron / Chromium flags
        md += "## Electron / Chromium 开启辅助功能前后\n\n"
        if flags.isEmpty {
            md += "本次运行没有遇到 Electron 或 Chromium 内核的 App。\n\n"
        } else {
            md += "| App | 类型 | 设置的属性 | 结果码 | 开启前可见字数 | 开启后可见字数 中位 |\n| --- | --- | --- | --- | --- | --- |\n"
            for fl in flags {
                let after = allObs.filter { $0.bundleId == fl.bundleId && $0.flagApplied != nil && $0.axMatched }.map { Double($0.axVisibleChars) }
                md += "| `\(fl.bundleId)` | \(fl.flavor) | \(fl.attribute) | \(fl.axError) | \(fl.charsBefore) | \(after.isEmpty ? "—" : String(Int(pct(after, 50)))) |\n"
            }
            md += "\n"
        }

        // Multi-window
        md += "## 多窗口\n\n"
        let visibleCounts = samples.map { Double($0.windows.count) }
        let matchable = allObs.filter { $0.skipped == nil }
        md += "| 项 | 值 |\n| --- | --- |\n"
        md += "| 每次采样同时可见的窗口数 平均 / 最大 | \(f(avg(visibleCounts))) / \(Int(visibleCounts.max() ?? 0)) |\n"
        md += "| 同时可见 ≥2 个窗口的采样占比 | \(p(visibleCounts.filter { $0 >= 2 }.count, visibleCounts.count)) |\n"
        md += "| 同时可见 ≥2 个 App 的采样占比 | \(p(samples.filter { Set($0.windows.map(\.bundleId)).count >= 2 }.count, samples.count)) |\n"
        md += "| 窗口分布在 ≥2 块屏幕的采样占比 | \(p(samples.filter { Set($0.windows.map(\.screen)).count >= 2 }.count, samples.count)) |\n"
        md += "| 能识别出焦点窗口的采样占比 | \(p(samples.filter { $0.windows.contains(where: \.focused) }.count, samples.count)) |\n"
        md += "| 屏幕窗口与辅助功能窗口的匹配率 | \(p(matchable.filter(\.axMatched).count, matchable.count)) |\n"
        md += "| 非焦点可见窗口的可见字数 中位 | \(Int(pct(matchable.filter { !$0.focused && $0.axMatched }.map { Double($0.axVisibleChars) }, 50))) |\n\n"

        // OCR
        md += "## OCR\n\n"
        md += "fallback = 辅助功能可见字数 < 50 时的兜底识别；compare = 每 5 分钟对焦点窗口识别一次，用来和辅助功能字数对比。\n\n"
        md += "| 类型 | 次数 | 成功率 | 截图耗时 中位 / p95 (ms) | 识别耗时 中位 / p95 (ms) | 识别字数 中位 | 平均置信度 | OCR 字数 ÷ AX 字数 中位 |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n"
        for reason in ["fallback", "compare"] {
            let rs = ocrs.filter { $0.reason == reason }
            let ok = rs.filter(\.ok)
            let ratios = ok.filter { $0.axVisibleChars > 0 }.map { Double($0.ocrChars) / Double($0.axVisibleChars) }
            md += "| \(reason) | \(rs.count) | \(p(ok.count, rs.count)) | \(f(pct(ok.map(\.captureMs), 50))) / \(f(pct(ok.map(\.captureMs), 95))) | \(f(pct(ok.map(\.ocrMs), 50))) / \(f(pct(ok.map(\.ocrMs), 95))) | \(Int(pct(ok.map { Double($0.ocrChars) }, 50))) | \(String(format: "%.2f", avg(ok.map(\.meanConfidence)))) | \(ratios.isEmpty ? "—" : String(format: "%.2f", pct(ratios, 50))) |\n"
        }
        let ocrErrors = Dictionary(grouping: ocrs.compactMap(\.error), by: { $0 }).map { "\($0.key) ×\($0.value.count)" }
        if !ocrErrors.isEmpty { md += "\n失败原因：\(ocrErrors.joined(separator: "；"))\n" }
        let fallbackApps = Dictionary(grouping: ocrs.filter { $0.reason == "fallback" }, by: \.bundleId)
            .map { "`\($0.key)` ×\($0.value.count)" }.sorted()
        if !fallbackApps.isEmpty { md += "\n触发兜底识别的 App：\(fallbackApps.joined(separator: "，"))\n" }
        md += "\n"

        // Chrome
        md += "## Chrome\n\n"
        md += "| 项 | 值 |\n| --- | --- |\n"
        let cOK = chromes.filter(\.ok)
        md += "| AppleScript 取网址 次数 / 成功率 | \(chromes.count) / \(p(cOK.count, chromes.count)) |\n"
        md += "| 耗时 中位 / p95 | \(f(pct(cOK.map(\.ms), 50))) / \(f(pct(cOK.map(\.ms), 95))) ms |\n"
        let cErr = Set(chromes.compactMap(\.errorNumber)).map(String.init).sorted().joined(separator: ", ")
        md += "| 错误码 | \(cErr.isEmpty ? "无" : cErr)（-1743 = 未获自动化授权） |\n"
        if let h = histories.last {
            md += "| History 库 Profile 数 / 可读 | \(h.profiles) / \(h.readable) |\n"
            md += "| 最近 24 小时访问次数 | \(h.visitsLast24h) |\n"
            md += "| 复制并读取耗时 | \(f(h.ms)) ms\(h.error.map { "（\($0)）" } ?? "") |\n"
        }
        md += "\n"

        // Resources
        md += "## 资源占用（探测程序自身）\n\n"
        let cpu = resources.map(\.cpuPercent), mem = resources.map(\.footprintMB)
        md += "| 项 | 值 |\n| --- | --- |\n"
        md += "| CPU 平均 / p95 / 最大 | \(f(avg(cpu)))% / \(f(pct(cpu, 95)))% / \(f(cpu.max() ?? 0))% |\n"
        md += "| 内存 中位 / 最大 | \(f(pct(mem, 50))) / \(f(mem.max() ?? 0)) MB |\n\n"

        // Data volume
        md += "## 数据量与模型用量估算\n\n"
        let newChars = allObs.reduce(0) { $0 + $1.newChars }
        let newCJK = allObs.reduce(0) { $0 + $1.newCJK }
        let tokens = Double(newCJK) + Double(newChars - newCJK) / 4
        let perHour = hours > 0 ? 1 / hours : 0
        md += "「新增字数」= 与同一窗口上一次相比新出现的行的字数，近似于白天整理时需要交给模型的增量。token 粗估：中文按 1 字 ≈ 1 token，其他按 4 字符 ≈ 1 token。\n\n"
        md += "| 项 | 合计 | 每小时 | 每 15 分钟 |\n| --- | --- | --- | --- |\n"
        md += "| 新增字数 | \(newChars) | \(Int(Double(newChars) * perHour)) | \(Int(Double(newChars) * perHour / 4)) |\n"
        md += "| 其中中文 | \(newCJK) | \(Int(Double(newCJK) * perHour)) | \(Int(Double(newCJK) * perHour / 4)) |\n"
        md += "| 估算 token | \(Int(tokens)) | \(Int(tokens * perHour)) | \(Int(tokens * perHour / 4)) |\n"

        let url = RecordStore.shared.dir.appendingPathComponent("report-\(fileStamp()).md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Helpers

    static func activeHours(_ samples: [SampleRec]) -> Double {
        var total = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) where b.ts - a.ts <= 120 { total += b.ts - a.ts }
        return total / 3600
    }

    static func pct(_ xs: [Double], _ q: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s[min(s.count - 1, Int((q / 100 * Double(s.count - 1)).rounded()))]
    }

    static func avg(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
    static func p(_ n: Int, _ d: Int) -> String { d == 0 ? "—" : String(format: "%.0f%%", Double(n) / Double(d) * 100) }
    static func f(_ x: Double) -> String { String(format: "%.1f", x) }
    static func yn(_ b: Bool) -> String { b ? "是" : "否" }

    static func fmtDate(_ ts: Double) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: Date(timeIntervalSince1970: ts))
    }

    static func fileStamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df.string(from: Date())
    }
}
