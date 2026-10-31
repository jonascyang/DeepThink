import Foundation

/// The kinds of 记录 the capture layer writes. Each kind has a Codable body stored in `Record.body`.
public enum RecordKind: String, Sendable {
    case windowText
    case focus
    case gap
    case presence
    case layout
}

public enum ReadMethod: String, Codable, Sendable {
    case accessibility
    case ocr
}

/// Text read from one window. `added` holds only the lines that were not in this window's previous record.
public struct WindowText: Codable, Sendable, Equatable {
    public var windowID: UInt32
    public var bundleID: String
    public var appName: String
    public var title: String?
    public var focused: Bool
    public var method: ReadMethod
    /// Chrome: active tab URL without query or fragment.
    public var url: String?
    public var added: [String]
    public var lineCount: Int
    public var visibleChars: Int
    /// The read stopped at its node or time budget, so some text may be missing.
    public var truncated: Bool

    public init(windowID: UInt32, bundleID: String, appName: String, title: String?, focused: Bool, method: ReadMethod,
                url: String? = nil, added: [String], lineCount: Int, visibleChars: Int, truncated: Bool) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.focused = focused
        self.method = method
        self.url = url
        self.added = added
        self.lineCount = lineCount
        self.visibleChars = visibleChars
        self.truncated = truncated
    }
}

/// The window the user is operating changed, or its title did.
/// For a window that must not be read, only `hidden` is set and the app and title stay empty.
public struct Focus: Codable, Sendable, Equatable {
    public var windowID: UInt32?
    public var bundleID: String
    public var appName: String
    public var title: String?
    public var hidden: Gap.Reason?

    public init(windowID: UInt32?, bundleID: String, appName: String, title: String?) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
    }

    /// Focus moved into a window on the 不看名单 or one that is never read.
    public static func hidden(windowID: UInt32?, reason: Gap.Reason) -> Focus {
        var focus = Focus(windowID: windowID, bundleID: "", appName: "", title: nil)
        focus.hidden = reason
        return focus
    }
}

/// Something could not be read. Recorded so the timeline shows the hole instead of inventing content.
public struct Gap: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable {
        case noAccessibilityPermission
        /// The accessibility read failed or timed out.
        case readFailed
        /// Accessibility returned almost nothing and OCR was off, not permitted, rate-limited or failed.
        case unreadable
        /// The app is on the 不看名单. Nothing else about the window is kept.
        case blocked
        /// A window that is never read: incognito, or a browser extension page such as a wallet.
        case neverRead
        /// The window is on screen but its app's accessibility tree has no matching window.
        case noAccessibilityWindow
    }

    public var reason: Reason
    public var bundleID: String?
    public var appName: String?
    public var windowID: UInt32?

    public init(reason: Reason, bundleID: String? = nil, appName: String? = nil, windowID: UInt32? = nil) {
        self.reason = reason
        self.bundleID = bundleID
        self.appName = appName
        self.windowID = windowID
    }
}

/// Input and machine state edges: no input, sleep, lock.
public struct Presence: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case idle, active, asleep, awake, locked, unlocked
    }

    public var state: State
    public var since: Date

    public init(state: State, since: Date) {
        self.state = state
        self.since = since
    }
}

extension Record {
    public init<Body: Encodable>(dayID: UUID, at: Date, kind: RecordKind, body: Body) throws {
        self.init(dayID: dayID, at: at, kind: kind.rawValue, body: try Event.encoder.encode(body))
    }

    public func decode<Body: Decodable>(_ type: Body.Type) throws -> Body {
        try Event.decoder.decode(type, from: body)
    }
}
