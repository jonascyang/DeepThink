import Foundation

// Everything written to disk is statistics only: no screen text, no window titles, no URLs.

struct WindowObs: Codable {
    var bundleId: String
    var app: String
    var focused: Bool
    var visibleFraction: Double
    var screen: Int
    var width: Int
    var height: Int
    var titleLength: Int
    var axMatched: Bool
    var axChars: Int
    var axVisibleChars: Int
    var axNodes: Int
    var axMs: Double
    var truncated: Bool
    var newChars: Int
    var newCJK: Int
    /// "electron" / "chromium" once AXManualAccessibility (or AXEnhancedUserInterface) was set for this app.
    var flagApplied: String?
    /// Reason the window was not read, e.g. "password-manager".
    var skipped: String?
}

struct SampleRec: Codable {
    var kind = "sample"
    var ts: Double
    var ms: Double
    var trigger: String
    var axTrusted: Bool
    var frontBundle: String?
    var screens: Int
    var windows: [WindowObs]
}

struct LaunchRec: Codable {
    var kind = "launch"
    var ts: Double
    var version: String
    var build: String
    var bundlePath: String
    var axTrusted: Bool
    var screenCaptureGranted: Bool
    var signingIdentifier: String?
    var signingCertificate: String?
    var teamId: String?
    var cdhash: String?
    var designatedRequirement: String?
    var osVersion: String
}

struct FlagRec: Codable {
    var kind = "flag"
    var ts: Double
    var bundleId: String
    var flavor: String
    var attribute: String
    var axError: Int32
    var charsBefore: Int
}

struct OCRRec: Codable {
    var kind = "ocr"
    var ts: Double
    /// "fallback": AX returned too little text; "compare": periodic OCR of the focused window to compare with AX.
    var reason: String
    var bundleId: String
    var ok: Bool
    var error: String?
    var captureMs: Double
    var ocrMs: Double
    var ocrChars: Int
    var axVisibleChars: Int
    var meanConfidence: Double
    var pixels: Int
}

struct ChromeRec: Codable {
    var kind = "chrome"
    var ts: Double
    var ok: Bool
    var ms: Double
    var windows: Int
    var errorNumber: Int?
}

struct HistoryRec: Codable {
    var kind = "history"
    var ts: Double
    var profiles: Int
    var readable: Int
    var visitsLast24h: Int
    var ms: Double
    var error: String?
}

struct ResourceRec: Codable {
    var kind = "resource"
    var ts: Double
    var cpuPercent: Double
    var footprintMB: Double
}

struct KindOnly: Decodable { var kind: String }

final class RecordStore {
    static let shared = RecordStore()

    let dir: URL
    let file: URL
    private let queue = DispatchQueue(label: "m0b.store")
    private let encoder = JSONEncoder()

    private init() {
        if let override = ProcessInfo.processInfo.environment["M0B_DATA_DIR"] {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            dir = base.appendingPathComponent("ThinkMyDay-M0bProbe", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("records.jsonl")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
    }

    func append<T: Encodable>(_ rec: T) {
        queue.async {
            guard var data = try? self.encoder.encode(rec) else { return }
            data.append(0x0A)
            guard let h = try? FileHandle(forWritingTo: self.file) else { return }
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        }
    }

    /// Waits for pending writes, then returns every line of the record file.
    func readAll() -> [Data] {
        queue.sync {
            guard let data = try? Data(contentsOf: file) else { return [] }
            return data.split(separator: 0x0A).map { Data($0) }
        }
    }

    func clear() {
        queue.sync {
            try? Data().write(to: file)
        }
    }
}
