import Foundation
import ScreenCaptureKit
import Vision

/// Captures a single window, runs on-device text recognition, and discards the image immediately.
final class OCRProbe {
    private let lock = NSLock()
    private var lastPerWindow: [CGWindowID: Date] = [:]
    private var lastAny = Date.distantPast
    private var running = false

    static let perWindowInterval: TimeInterval = 30
    static let globalInterval: TimeInterval = 5
    static let timeout: TimeInterval = 10

    func request(window: CGWin, bundle: String, reason: String, axVisibleChars: Int) {
        lock.lock()
        let now = Date()
        let allowed = !running
            && now.timeIntervalSince(lastAny) >= Self.globalInterval
            && now.timeIntervalSince(lastPerWindow[window.id] ?? .distantPast) >= Self.perWindowInterval
        if allowed {
            running = true
            lastAny = now
            lastPerWindow[window.id] = now
        }
        lock.unlock()
        guard allowed else { return }

        Task.detached(priority: .utility) {
            // A hung ScreenCaptureKit call must not block every later OCR request.
            let rec = await withTaskGroup(of: OCRRec.self) { group in
                group.addTask { await Self.run(window: window, bundle: bundle, reason: reason, axVisibleChars: axVisibleChars) }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
                    return OCRRec(ts: Date().timeIntervalSince1970, reason: reason, bundleId: bundle, ok: false, error: "timeout",
                                  captureMs: Self.timeout * 1000, ocrMs: 0, ocrChars: 0, axVisibleChars: axVisibleChars,
                                  meanConfidence: 0, pixels: 0)
                }
                let first = await group.next()!
                group.cancelAll()
                return first
            }
            RecordStore.shared.append(rec)
            self.lock.withLock { self.running = false }
        }
    }

    private static func run(window: CGWin, bundle: String, reason: String, axVisibleChars: Int) async -> OCRRec {
        var rec = OCRRec(ts: Date().timeIntervalSince1970, reason: reason, bundleId: bundle, ok: false, error: nil,
                         captureMs: 0, ocrMs: 0, ocrChars: 0, axVisibleChars: axVisibleChars, meanConfidence: 0, pixels: 0)
        guard CGPreflightScreenCaptureAccess() else {
            rec.error = "no-screen-recording-permission"
            return rec
        }
        let captureStart = DispatchTime.now().uptimeNanoseconds
        let image: CGImage
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else {
                rec.error = "window-not-shareable"
                return rec
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            config.width = Int(window.bounds.width * scale)
            config.height = Int(window.bounds.height * scale)
            config.showsCursor = false
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            rec.error = "capture: \(error.localizedDescription)"
            return rec
        }
        rec.captureMs = AXReader.elapsedMs(since: captureStart)
        rec.pixels = image.width * image.height

        let ocrStart = DispatchTime.now().uptimeNanoseconds
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            rec.error = "vision: \(error.localizedDescription)"
            return rec
        }
        // The image goes out of scope here and is never written to disk.
        rec.ocrMs = AXReader.elapsedMs(since: ocrStart)
        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        rec.ocrChars = candidates.reduce(0) { $0 + $1.string.count }
        if !candidates.isEmpty {
            rec.meanConfidence = Double(candidates.reduce(Float(0)) { $0 + $1.confidence }) / Double(candidates.count)
        }
        rec.ok = true
        return rec
    }
}
