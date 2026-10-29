import AppKit
import Foundation
import Security
import SQLite3

enum ChromeProbe {
    /// Asks Chrome for the active-tab URL of every window via AppleScript. Only counts are recorded.
    /// Must run on the main thread; does nothing when Chrome is not running (a `tell` would launch it).
    static func run() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first != nil else { return }
        let source = """
        tell application id "com.google.Chrome"
            set out to {}
            repeat with w in windows
                set end of out to (URL of active tab of w)
            end repeat
            return out
        end tell
        """
        let start = DispatchTime.now().uptimeNanoseconds
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        let ms = AXReader.elapsedMs(since: start)
        RecordStore.shared.append(ChromeRec(ts: Date().timeIntervalSince1970, ok: err == nil, ms: (ms * 10).rounded() / 10,
                                            windows: result?.numberOfItems ?? 0,
                                            errorNumber: err?[NSAppleScript.errorNumber] as? Int))
    }
}

enum HistoryProbe {
    /// Copies each Chrome profile's History database to a temp file and counts visits in the last 24 hours.
    static func run() {
        let start = DispatchTime.now().uptimeNanoseconds
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        var rec = HistoryRec(ts: Date().timeIntervalSince1970, profiles: 0, readable: 0, visitsLast24h: 0, ms: 0, error: nil)
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        } catch {
            rec.error = "list: \(error.localizedDescription)"
            RecordStore.shared.append(rec)
            return
        }
        // Chrome stores microseconds since 1601-01-01.
        let cutoff = Int64((Date().timeIntervalSince1970 - 86_400 + 11_644_473_600) * 1_000_000)
        for name in entries where name == "Default" || name.hasPrefix("Profile ") {
            let src = root.appendingPathComponent(name).appendingPathComponent("History")
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            rec.profiles += 1
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("m0b-history-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tmp) }
            do {
                try FileManager.default.copyItem(at: src, to: tmp)
            } catch {
                rec.error = "copy: \(error.localizedDescription)"
                continue
            }
            var db: OpaquePointer?
            guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                rec.error = "open failed"
                sqlite3_close(db)
                continue
            }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM visits WHERE visit_time > ?", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, cutoff)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    rec.visitsLast24h += Int(sqlite3_column_int64(stmt, 0))
                    rec.readable += 1
                }
            } else {
                rec.error = "query failed"
            }
            sqlite3_finalize(stmt)
            sqlite3_close(db)
        }
        rec.ms = AXReader.elapsedMs(since: start)
        RecordStore.shared.append(rec)
    }
}

final class ResourceProbe {
    private var lastCPU: Double?
    private var lastWall: Double?

    func tick() {
        var ru = rusage()
        getrusage(RUSAGE_SELF, &ru)
        let cpu = Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6
        let wall = ProcessInfo.processInfo.systemUptime
        defer { lastCPU = cpu; lastWall = wall }
        guard let lc = lastCPU, let lw = lastWall, wall > lw else { return }
        RecordStore.shared.append(ResourceRec(ts: Date().timeIntervalSince1970,
                                              cpuPercent: ((cpu - lc) / (wall - lw) * 1000).rounded() / 10,
                                              footprintMB: (Self.footprintMB() * 10).rounded() / 10))
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}

enum LaunchProbe {
    /// Records permission state and this build's code-signing identity, for the "授权是否保留" test.
    static func run() {
        let info = Bundle.main.infoDictionary ?? [:]
        var rec = LaunchRec(ts: Date().timeIntervalSince1970,
                            version: info["CFBundleShortVersionString"] as? String ?? "?",
                            build: info["CFBundleVersion"] as? String ?? "?",
                            bundlePath: Bundle.main.bundlePath,
                            axTrusted: AXIsProcessTrusted(),
                            screenCaptureGranted: CGPreflightScreenCaptureAccess(),
                            osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        var code: SecCode?
        var staticCode: SecStaticCode?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode {
            var dict: CFDictionary?
            if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &dict) == errSecSuccess,
               let d = dict as? [String: Any] {
                rec.signingIdentifier = d[kSecCodeInfoIdentifier as String] as? String
                rec.teamId = d[kSecCodeInfoTeamIdentifier as String] as? String
                rec.cdhash = (d[kSecCodeInfoUnique as String] as? Data)?.map { String(format: "%02x", $0) }.joined()
                if let certs = d[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first {
                    rec.signingCertificate = SecCertificateCopySubjectSummary(leaf) as String?
                } else {
                    rec.signingCertificate = "ad-hoc"
                }
            }
            var req: SecRequirement?
            var text: CFString?
            if SecCodeCopyDesignatedRequirement(staticCode, [], &req) == errSecSuccess, let req,
               SecRequirementCopyString(req, [], &text) == errSecSuccess {
                rec.designatedRequirement = text as String?
            }
        }
        RecordStore.shared.append(rec)
    }
}
