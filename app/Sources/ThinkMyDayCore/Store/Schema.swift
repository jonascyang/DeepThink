import Foundation

/// Forward-only migrations. Entry `i` takes the database from version `i` to `i + 1`; never edit a shipped entry.
enum Schema {
    static let migrations: [String] = [
        // v1: event log, projection cursors, 复盘日 and 记录.
        """
        CREATE TABLE events (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            at      REAL NOT NULL,
            day_id  TEXT NOT NULL,
            kind    TEXT NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE INDEX events_day ON events(day_id);
        CREATE TABLE cursors (
            name     TEXT PRIMARY KEY,
            event_id INTEGER NOT NULL
        );
        CREATE TABLE review_days (
            id            TEXT PRIMARY KEY,
            started_at    REAL NOT NULL,
            ended_at      REAL,
            planned_start REAL
        );
        CREATE TABLE records (
            id       TEXT PRIMARY KEY,
            day_id   TEXT NOT NULL REFERENCES review_days(id),
            at       REAL NOT NULL,
            kind     TEXT NOT NULL,
            body     BLOB NOT NULL,
            event_id INTEGER NOT NULL
        );
        CREATE INDEX records_day_at ON records(day_id, at);
        """,
    ]

    static var currentVersion: Int { migrations.count }

    /// Applies every migration above the database's `user_version`, each in its own transaction.
    static func migrate(_ db: SQLiteConnection, migrations: [String] = migrations) throws {
        let version = Int(try db.query("PRAGMA user_version").first?.first?.int ?? 0)
        guard version <= migrations.count else {
            throw StoreError.newerSchema(found: version, supported: migrations.count)
        }
        for target in version..<migrations.count {
            try db.transaction {
                try db.execute(migrations[target])
                try db.execute("PRAGMA user_version = \(target + 1)")
            }
        }
    }
}

public enum StoreError: Error, Equatable, Sendable {
    /// The database was written by a newer build; opening it could lose data.
    case newerSchema(found: Int, supported: Int)
    case unknownEventKind(String)
    case dayNotFound(UUID)
    case dayAlreadyEnded(UUID)
    /// The day is being recorded; end it before deleting it.
    case dayIsOpen(UUID)
    /// The database holds encrypted data but the Keychain has no key for it.
    case keyMissing
    /// The key does not decrypt the data.
    case wrongKey
    case encryptionFailed
    case keychain(OSStatus)
}
