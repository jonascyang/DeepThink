import Foundation

/// A file the user had in front of them: open in a window, or selected in Finder (#15).
/// Facts only; why it was opened is for the AI to work out.
public struct OpenedFile: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// The window's document (Preview, Quick Look, editors).
        case document
        /// The folder a Finder window shows.
        case finderFolder
        /// An item selected in Finder.
        case finderSelection
    }

    public var windowID: UInt32
    public var bundleID: String
    public var appName: String
    public var source: Source
    public var path: String
    public var name: String
    public var contentType: String?
    public var size: Int?
    public var created: Date?
    /// Where the file was downloaded from (macOS kMDItemWhereFroms), queries removed.
    public var downloadedFrom: [String]?
    public var downloadedAt: Date?
    /// The app that downloaded it, from the quarantine record (e.g. Google Chrome, 微信).
    public var downloadedBy: String?
    public var place: Place?

    public init(windowID: UInt32, bundleID: String, appName: String, source: Source, path: String, name: String) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.appName = appName
        self.source = source
        self.path = path
        self.name = name
    }
}

/// Remembers which files each window showed, so a file is recorded when it appears, not every sample.
public struct OpenedFileHistory: Sendable {
    private var seen: [UInt32: Set<String>] = [:]

    public init() {}

    /// The entries of `files` (keyed by source and path) that this window did not show last time.
    public mutating func new(window: UInt32, files: [(OpenedFile.Source, String)]) -> [(OpenedFile.Source, String)] {
        let keys = files.map { "\($0.0.rawValue)|\($0.1)" }
        let before = seen[window] ?? []
        seen[window] = Set(keys)
        return zip(files, keys).filter { !before.contains($0.1) }.map(\.0)
    }

    public mutating func reset() { seen = [:] }
}
