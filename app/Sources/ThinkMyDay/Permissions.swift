import AppKit
import ApplicationServices

/// The system permissions the app uses. Only accessibility is required; without the others the matching capability is marked unavailable.
enum Permission: CaseIterable {
    case accessibility, screenRecording, chromeAutomation

    var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .screenRecording: "屏幕录制"
        case .chromeAutomation: "自动化 · Google Chrome"
        }
    }

    var required: Bool { self == .accessibility }

    var settingsURL: URL {
        let pane = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        case .chromeAutomation: "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

enum PermissionState: Equatable, Sendable {
    case granted
    case denied
    /// Never asked yet; requesting shows the system prompt.
    case notDetermined
    /// Cannot be checked right now, e.g. Chrome is not running.
    case unknown(String)

    var label: String {
        switch self {
        case .granted: "已授权"
        case .denied: "未授权"
        case .notDetermined: "未授权"
        case .unknown(let why): why
        }
    }
}

enum Permissions {
    static let chromeBundleID = "com.google.Chrome"

    static func accessibility() -> PermissionState { AXIsProcessTrusted() ? .granted : .denied }

    static func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func screenRecording() -> PermissionState { CGPreflightScreenCaptureAccess() ? .granted : .denied }

    static func requestScreenRecording() { _ = CGRequestScreenCaptureAccess() }

    /// Asks the Apple Event system whether we may script Chrome. Can block while the user answers a prompt, so never call it on the main thread.
    static func chromeAutomation(ask: Bool) -> PermissionState {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: chromeBundleID).first != nil else {
            return .unknown("Chrome 未运行")
        }
        var target = AEAddressDesc()
        let created = chromeBundleID.withCString {
            AECreateDesc(DescType(typeApplicationBundleID), $0, chromeBundleID.utf8.count, &target)
        }
        guard created == noErr else { return .unknown("无法检查") }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .unknown("Chrome 未运行")
        default: return .unknown("无法检查")
        }
    }
}
