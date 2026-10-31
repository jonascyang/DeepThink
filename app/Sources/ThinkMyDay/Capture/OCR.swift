import Foundation
import OSLog
import ScreenCaptureKit
import Vision

/// Captures one window and recognises its text on this Mac. The image is never written to disk.
enum OCR {
    static let timeout: TimeInterval = 10
    private static let log = Logger(subsystem: "com.jonascyang.thinkmyday", category: "ocr")

    /// Recognised lines, or nil on failure or timeout.
    static func read(windowID: CGWindowID, bounds: CGRect) async -> [String]? {
        // A hung ScreenCaptureKit call must not block later reads (seen in M0b).
        await withTaskGroup(of: [String]?.self) { group in
            group.addTask { await run(windowID: windowID, bounds: bounds) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func run(windowID: CGWindowID, bounds: CGRect) async -> [String]? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                log.notice("window \(windowID) not shareable")
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            config.width = Int(bounds.width * scale)
            config.height = Int(bounds.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        } catch {
            log.notice("OCR failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
