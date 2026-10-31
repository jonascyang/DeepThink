import AppKit
import ApplicationServices
import CoreServices
import SQLite3
import ThinkMyDayCore

/// Which file a window shows, what Finder has selected, and what macOS knows about a file (#15).
enum Files {
    /// The document behind a window (AXDocument): Preview, Quick Look, TextEdit, most document apps; for Finder, the folder.
    static func document(of window: AXUIElement) -> String? {
        guard let raw = AX.attr(window, kAXDocumentAttribute) as? String else { return nil }
        if let url = URL(string: raw), url.isFileURL { return url.path }
        return raw.hasPrefix("/") ? raw : nil
    }

    /// Paths of the items selected in a Finder window. Looks for lists, outlines and icon views a few levels down.
    static func finderSelection(in window: AXUIElement, folder: String?) -> [String] {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var paths: [String] = []
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let (el, depth) = queue.removeFirst()
            visited += 1
            let selected = (AX.attr(el, kAXSelectedRowsAttribute) as? [AXUIElement]) ?? (AX.attr(el, kAXSelectedChildrenAttribute) as? [AXUIElement]) ?? []
            for item in selected {
                if let path = itemPath(item, folder: folder) { paths.append(path) }
            }
            if !paths.isEmpty { break }
            if depth < 8, let kids = AX.attr(el, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: kids.map { ($0, depth + 1) })
            }
        }
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    /// A Finder item's URL if it exposes one, otherwise its visible name joined to the window's folder.
    private static func itemPath(_ item: AXUIElement, folder: String?) -> String? {
        if let url = AX.attr(item, kAXURLAttribute) as? URL, url.isFileURL { return url.path }
        if let raw = AX.attr(item, kAXURLAttribute) as? String, let url = URL(string: raw), url.isFileURL { return url.path }
        var name = (AX.attr(item, kAXFilenameAttribute) as? String) ?? (AX.attr(item, kAXTitleAttribute) as? String)
        if name?.isEmpty ?? true {
            // A list row: the name is the first text in its first cell.
            var stack = (AX.attr(item, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            var steps = 0
            while let el = stack.first, steps < 30 {
                stack.removeFirst()
                steps += 1
                if let v = AX.attr(el, kAXValueAttribute) as? String, !v.isEmpty { name = v; break }
                stack.insert(contentsOf: (AX.attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [], at: 0)
            }
        }
        guard let name, !name.isEmpty else { return nil }
        return folder.map { ($0 as NSString).appendingPathComponent(name) } ?? name
    }

    /// Fills in type, size, dates and download source from Spotlight metadata. A path that does not exist is left as it is.
    static func describe(_ file: inout OpenedFile) {
        guard file.path.hasPrefix("/"), let item = MDItemCreateWithURL(nil, URL(fileURLWithPath: file.path) as CFURL) else { return }
        func attr(_ key: CFString) -> Any? { MDItemCopyAttribute(item, key) }
        file.contentType = attr(kMDItemContentType) as? String
        file.size = (attr(kMDItemFSSize) as? NSNumber)?.intValue
        file.created = attr(kMDItemFSCreationDate) as? Date
        if let froms = attr(kMDItemWhereFroms) as? [String], !froms.isEmpty {
            file.downloadedFrom = froms.map(URLCleaner.clean)
        }
        file.downloadedAt = (attr("kMDItemDownloadedDate" as CFString) as? [Date])?.first ?? attr("kMDItemDownloadedDate" as CFString) as? Date
        if let q = quarantine(file.path) {
            file.downloadedBy = q.agent ?? file.downloadedBy
            file.downloadedAt = file.downloadedAt ?? q.date
            if file.downloadedFrom == nil, !q.urls.isEmpty { file.downloadedFrom = q.urls.map(URLCleaner.clean) }
        }
    }

    /// The quarantine mark macOS puts on downloaded files ("flags;hex time;agent;event id") and, through the event id,
    /// the download and page URLs in the system's QuarantineEventsV2 database. Many files carry this but no kMDItemWhereFroms.
    static func quarantine(_ path: String) -> (agent: String?, date: Date?, urls: [String])? {
        var buffer = [UInt8](repeating: 0, count: 1024)
        let n = getxattr(path, "com.apple.quarantine", &buffer, buffer.count, 0, 0)
        guard n > 0 else { return nil }
        let parts = String(decoding: buffer.prefix(n), as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let date = UInt64(parts[1], radix: 16).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        // The mark's agent is only the download app when the system has a download event for it; files that
        // Preview or a screenshot marked carry an agent but were never downloaded.
        var agent: String?
        var urls: [String] = []
        if parts.count >= 4, !parts[3].isEmpty {
            let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2").path
            var handle: OpaquePointer?
            if sqlite3_open_v2(db, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                var stmt: OpaquePointer?
                let sql = "SELECT LSQuarantineOriginURLString, LSQuarantineDataURLString, LSQuarantineAgentName FROM LSQuarantineEvent WHERE LSQuarantineEventIdentifier = ?"
                if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, parts[3], -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        for column in Int32(0)...1 {
                            if let text = sqlite3_column_text(stmt, column) { urls.append(String(cString: text)) }
                        }
                        agent = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? (parts[2].isEmpty ? nil : parts[2])
                    }
                }
                sqlite3_finalize(stmt)
            }
            sqlite3_close(handle)
        }
        guard agent != nil || !urls.isEmpty else { return nil }
        return (agent, date, urls.filter { !$0.isEmpty })
    }

    /// Length of the text in the focused text field of an app, or nil when the focus is elsewhere or on a password field.
    static func focusedFieldLength(pid: pid_t) -> Int? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let raw = AX.attr(app, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let el = raw as! AXUIElement
        let role = AX.attr(el, kAXRoleAttribute) as? String ?? ""
        let subrole = AX.attr(el, kAXSubroleAttribute) as? String ?? ""
        guard ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(role), subrole != kAXSecureTextFieldSubrole else { return nil }
        if let count = AX.attr(el, kAXNumberOfCharactersAttribute) as? Int { return count }
        return (AX.attr(el, kAXValueAttribute) as? String)?.count
    }
}

/// System-wide scroll and click counters. Only how many, never where or on what.
struct InputCounters {
    var scrolls: UInt32
    var clicks: UInt32

    static func now() -> InputCounters {
        func count(_ type: CGEventType) -> UInt32 { CGEventSource.counterForEventType(.combinedSessionState, eventType: type) }
        return InputCounters(scrolls: count(.scrollWheel),
                             clicks: count(.leftMouseDown) &+ count(.rightMouseDown) &+ count(.otherMouseDown))
    }

    /// The pointer in CG global coordinates (top-left origin).
    static func pointer(screens: [CGRect]) -> CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = screens.first?.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
