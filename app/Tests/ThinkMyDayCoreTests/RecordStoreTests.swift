import Foundation
import Testing
@testable import ThinkMyDayCore

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("tmd-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("thinkmyday.sqlite")
}

private func record(_ day: ReviewDay, _ seconds: Double, _ text: String = "hello") -> Record {
    Record(dayID: day.id, at: day.startedAt.addingTimeInterval(seconds), kind: "windowText", body: Data(text.utf8))
}

@Suite struct RecordStoreTests {
    let day = ReviewDay(startedAt: Date(timeIntervalSince1970: 1_793_400_000), plannedStart: Date(timeIntervalSince1970: 1_793_396_400))

    @Test func newDatabaseIsAtCurrentSchema() async throws {
        let store = try RecordStore(url: tempURL())
        #expect(try await store.schemaVersion == Schema.currentVersion)
    }

    @Test func writesAndReadsDaysAndRecords() async throws {
        let store = try RecordStore(url: tempURL())
        try await store.append(.dayStarted(day))
        #expect(try await store.openDay() == day)

        let a = record(day, 5, "第一条"), b = record(day, 10, "second")
        try await store.append(.recordCaptured(b))
        try await store.append(.recordCaptured(a))
        #expect(try await store.records(dayID: day.id) == [a, b])

        let end = day.startedAt.addingTimeInterval(3600)
        try await store.append(.dayEnded(dayID: day.id, at: end))
        #expect(try await store.openDay() == nil)
        #expect(try await store.days().first?.endedAt == end)
        #expect(try await store.verify().isEmpty)
    }

    @Test func dataSurvivesReopening() async throws {
        let url = tempURL()
        do {
            let store = try RecordStore(url: url)
            try await store.append(.dayStarted(day))
            try await store.append(.recordCaptured(record(day, 1)))
        }
        let reopened = try RecordStore(url: url)
        #expect(try await reopened.records(dayID: day.id).count == 1)
        #expect(try await reopened.openDay()?.id == day.id)
    }

    @Test func invalidEventWritesNothing() async throws {
        let store = try RecordStore(url: tempURL())
        let orphan = Record(dayID: UUID(), at: Date(), kind: "windowText", body: Data())
        await #expect(throws: SQLiteError.self) { try await store.append(.recordCaptured(orphan)) }
        await #expect(throws: StoreError.dayNotFound(day.id)) { try await store.append(.dayEnded(dayID: day.id, at: Date())) }
        #expect(try await store.eventCount() == 0)

        try await store.append(.dayStarted(day))
        try await store.append(.dayEnded(dayID: day.id, at: Date()))
        await #expect(throws: StoreError.dayAlreadyEnded(day.id)) { try await store.append(.dayEnded(dayID: day.id, at: Date())) }
        #expect(try await store.eventCount() == 2)
    }

    @Test func projectionsRebuildFromEvents() async throws {
        let store = try RecordStore(url: tempURL())
        try await store.append(.dayStarted(day))
        for i in 0..<50 { try await store.append(.recordCaptured(record(day, Double(i), "line \(i)"))) }
        let before = try await store.records(dayID: day.id)

        try await store.rebuildProjections()
        #expect(try await store.records(dayID: day.id) == before)
        #expect(try await store.days() == [day])
        #expect(try await store.verify().isEmpty)
    }

    @Test func reopeningCatchesUpProjectionsThatFellBehind() async throws {
        let url = tempURL()
        do {
            let store = try RecordStore(url: url)
            try await store.append(.dayStarted(day))
            try await store.append(.recordCaptured(record(day, 1)))
        }
        // Simulate projections lagging the log, e.g. after a projection bug was fixed and its table cleared.
        let raw = try SQLiteConnection(path: url.path)
        try raw.execute("DELETE FROM records; DELETE FROM review_days; DELETE FROM cursors")

        let reopened = try RecordStore(url: url)
        #expect(try await reopened.records(dayID: day.id).count == 1)
        #expect(try await reopened.verify().isEmpty)
    }
}

@Suite struct SchemaTests {
    @Test func migratesForwardFromOlderVersion() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try SQLiteConnection(path: url.path)
        try Schema.migrate(db, migrations: Array(Schema.migrations.prefix(1)))
        try db.run("INSERT INTO review_days (id, started_at) VALUES ('x', 1)")

        let v2 = Schema.migrations + ["ALTER TABLE review_days ADD COLUMN note TEXT"]
        try Schema.migrate(db, migrations: v2)
        #expect(try db.query("PRAGMA user_version").first?.first?.int == 2)
        #expect(try db.query("SELECT id, note FROM review_days") == [[.text("x"), .null]])

        // Running again is a no-op.
        try Schema.migrate(db, migrations: v2)
        #expect(try db.query("PRAGMA user_version").first?.first?.int == 2)
    }

    @Test func refusesNewerDatabase() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try SQLiteConnection(path: url.path)
        try db.execute("PRAGMA user_version = 99")
        #expect(throws: StoreError.newerSchema(found: 99, supported: Schema.currentVersion)) { try RecordStore(url: url) }
    }

    @Test func failedMigrationLeavesVersionUnchanged() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try SQLiteConnection(path: url.path)
        try Schema.migrate(db)
        #expect(throws: SQLiteError.self) { try Schema.migrate(db, migrations: Schema.migrations + ["CREATE TABLE bad (; nonsense"]) }
        #expect(try db.query("PRAGMA user_version").first?.first?.int == Int64(Schema.currentVersion))
    }
}
