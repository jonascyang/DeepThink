import Foundation

/// The single local database. Writes append an event and update the projections in one transaction,
/// so a crash leaves either both or neither; `replay()` catches projections up if they ever fall behind.
public actor RecordStore {
    public let url: URL
    private let db: SQLiteConnection
    private static let projection = "main"

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteConnection(path: url.path)
        try db.execute("PRAGMA journal_mode = WAL")
        // FULL: a committed record survives power loss, not only a process crash.
        try db.execute("PRAGMA synchronous = FULL")
        try db.execute("PRAGMA foreign_keys = ON")
        try Schema.migrate(db)
        try Self.catchUp(db)
    }

    /// Default location: ~/Library/Application Support/ThinkMyDay/thinkmyday.sqlite, or $TMD_DATA_DIR for development.
    public static func defaultURL() -> URL {
        let dir: URL
        if let override = ProcessInfo.processInfo.environment["TMD_DATA_DIR"] {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ThinkMyDay", isDirectory: true)
        }
        return dir.appendingPathComponent("thinkmyday.sqlite")
    }

    public var schemaVersion: Int {
        get throws { Int(try db.query("PRAGMA user_version").first?.first?.int ?? 0) }
    }

    // MARK: - Writing

    /// Appends one event and applies it. Throws, and writes nothing, if the event is invalid.
    @discardableResult
    public func append(_ event: Event) throws -> Int64 {
        try db.transaction { try insert(event) }
    }

    /// Appends several events atomically: all of them or none.
    public func append(_ events: [Event]) throws {
        try db.transaction {
            for event in events { _ = try insert(event) }
        }
    }

    /// 开启一天. A day the user forgot to end closes at this same moment, in the same transaction.
    /// Returns the new day and, if there was one, the day that was closed.
    @discardableResult
    public func startDay(at now: Date, plannedStart: PlannedStart?) throws -> (started: ReviewDay, ended: ReviewDay?) {
        let open = try openDay()
        let day = ReviewDay(startedAt: now, plannedStart: plannedStart?.occurrence(near: now))
        var events: [Event] = []
        if let open { events.append(.dayEnded(dayID: open.id, at: now)) }
        events.append(.dayStarted(day))
        try append(events)
        return (day, open.map { var d = $0; d.endedAt = now; return d })
    }

    /// 结束一天. Returns the day that was ended, or nil if none was open.
    @discardableResult
    public func endDay(at now: Date) throws -> ReviewDay? {
        guard var open = try openDay() else { return nil }
        try append(.dayEnded(dayID: open.id, at: now))
        open.endedAt = now
        return open
    }

    /// Applies any events the projections have not seen yet.
    public func replay() throws { try Self.catchUp(db) }

    /// Drops the projections and rebuilds them from the event log.
    public func rebuildProjections() throws {
        try db.transaction {
            try db.execute("DELETE FROM records; DELETE FROM review_days; DELETE FROM cursors")
        }
        try Self.catchUp(db)
    }

    // MARK: - Reading

    public func days() throws -> [ReviewDay] {
        try db.query("SELECT id, started_at, ended_at, planned_start FROM review_days ORDER BY started_at").map(Self.day)
    }

    /// The day being recorded now, if any.
    public func openDay() throws -> ReviewDay? {
        try db.query("SELECT id, started_at, ended_at, planned_start FROM review_days WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1")
            .first.map(Self.day)
    }

    public func records(dayID: UUID) throws -> [Record] {
        try db.query("SELECT id, day_id, at, kind, body FROM records WHERE day_id = ? ORDER BY at, rowid", [.text(dayID.uuidString)])
            .map { r in
                Record(id: UUID(uuidString: r[0].text ?? "") ?? UUID(), dayID: UUID(uuidString: r[1].text ?? "") ?? UUID(),
                       at: Date(timeIntervalSince1970: r[2].double ?? 0), kind: r[3].text ?? "", body: r[4].blob ?? Data())
            }
    }

    public func eventCount() throws -> Int {
        Int(try db.query("SELECT count(*) FROM events").first?.first?.int ?? 0)
    }

    /// `PRAGMA integrity_check` plus a check that every event reached the projections.
    public func verify() throws -> [String] {
        var problems: [String] = []
        let integrity = try db.query("PRAGMA integrity_check").compactMap { $0.first?.text }
        if integrity != ["ok"] { problems += integrity }
        let lastEvent = try db.query("SELECT coalesce(max(id), 0) FROM events").first?.first?.int ?? 0
        let cursor = try db.query("SELECT event_id FROM cursors WHERE name = ?", [.text(Self.projection)]).first?.first?.int ?? 0
        if cursor != lastEvent { problems.append("projection cursor \(cursor) behind last event \(lastEvent)") }
        let captured = try db.query("SELECT count(*) FROM events WHERE kind = 'recordCaptured'").first?.first?.int ?? 0
        let projected = try db.query("SELECT count(*) FROM records").first?.first?.int ?? 0
        if captured != projected { problems.append("\(captured) recordCaptured events but \(projected) records") }
        return problems
    }

    // MARK: - Projection

    /// Writes the event and applies it. Callers wrap this in a transaction.
    /// Record bodies are redacted here, so no write path can store a secret (PRD §10, #9).
    private func insert(_ event: Event) throws -> Int64 {
        var event = event
        if case .recordCaptured(let record) = event { event = .recordCaptured(try record.redacted()) }
        try db.run("INSERT INTO events (at, day_id, kind, payload) VALUES (?, ?, ?, ?)",
                   [.double(event.at.timeIntervalSince1970), .text(event.dayID.uuidString), .text(event.kind), .blob(try event.payload())])
        let id = db.lastInsertRowID
        try Self.apply(event, id: id, db)
        try Self.setCursor(id, db)
        return id
    }

    private static func catchUp(_ db: SQLiteConnection) throws {
        let cursor = try db.query("SELECT event_id FROM cursors WHERE name = ?", [.text(projection)]).first?.first?.int ?? 0
        let pending = try db.query("SELECT id, kind, payload FROM events WHERE id > ? ORDER BY id", [.int(cursor)])
        guard !pending.isEmpty else { return }
        try db.transaction {
            for row in pending {
                let id = row[0].int ?? 0
                try apply(try Event(kind: row[1].text ?? "", payload: row[2].blob ?? Data()), id: id, db)
                try setCursor(id, db)
            }
        }
    }

    private static func apply(_ event: Event, id: Int64, _ db: SQLiteConnection) throws {
        switch event {
        case .dayStarted(let day):
            try db.run("INSERT INTO review_days (id, started_at, ended_at, planned_start) VALUES (?, ?, ?, ?)",
                       [.text(day.id.uuidString), .double(day.startedAt.timeIntervalSince1970),
                        day.endedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                        day.plannedStart.map { .double($0.timeIntervalSince1970) } ?? .null])
        case .dayEnded(let dayID, let at):
            let rows = try db.query("SELECT ended_at FROM review_days WHERE id = ?", [.text(dayID.uuidString)])
            guard let row = rows.first else { throw StoreError.dayNotFound(dayID) }
            guard row[0] == .null else { throw StoreError.dayAlreadyEnded(dayID) }
            try db.run("UPDATE review_days SET ended_at = ? WHERE id = ?", [.double(at.timeIntervalSince1970), .text(dayID.uuidString)])
        case .recordCaptured(let r):
            // Records exist only inside an open 复盘日 (PRD §5.2): nothing before 开启一天 or after 结束一天.
            let rows = try db.query("SELECT ended_at FROM review_days WHERE id = ?", [.text(r.dayID.uuidString)])
            guard let row = rows.first else { throw StoreError.dayNotFound(r.dayID) }
            guard row[0] == .null else { throw StoreError.dayAlreadyEnded(r.dayID) }
            try db.run("INSERT INTO records (id, day_id, at, kind, body, event_id) VALUES (?, ?, ?, ?, ?, ?)",
                       [.text(r.id.uuidString), .text(r.dayID.uuidString), .double(r.at.timeIntervalSince1970),
                        .text(r.kind), .blob(r.body), .int(id)])
        }
    }

    private static func setCursor(_ id: Int64, _ db: SQLiteConnection) throws {
        try db.run("INSERT INTO cursors (name, event_id) VALUES (?, ?) ON CONFLICT(name) DO UPDATE SET event_id = excluded.event_id",
                   [.text(projection), .int(id)])
    }

    private static func day(_ r: [SQLValue]) -> ReviewDay {
        ReviewDay(id: UUID(uuidString: r[0].text ?? "") ?? UUID(),
                  startedAt: Date(timeIntervalSince1970: r[1].double ?? 0),
                  endedAt: r[2].double.map(Date.init(timeIntervalSince1970:)),
                  plannedStart: r[3].double.map(Date.init(timeIntervalSince1970:)))
    }
}
