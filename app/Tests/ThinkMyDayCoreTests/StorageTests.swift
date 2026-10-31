import CryptoKit
import Foundation
import Testing
@testable import ThinkMyDayCore

private func files(next url: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(url.lastPathComponent) }
}

private func bytesContain(_ needle: Data, near url: URL) throws -> Bool {
    try files(next: url).contains { try Data(contentsOf: $0).range(of: needle) != nil }
}

private func text(_ day: ReviewDay, _ at: Date, _ line: String) throws -> Record {
    try Record(dayID: day.id, at: at, kind: .windowText,
               body: WindowText(windowID: 1, bundleID: "test", appName: "test", title: nil, focused: true, method: .accessibility,
                                added: [line], lineCount: 1, visibleChars: line.count, truncated: false))
}

@Suite struct EncryptionTests {
    @Test func contentIsNotStoredInPlaintext() async throws {
        let url = tempURL()
        let store = try RecordStore(url: url, keys: InMemoryKeyStore())
        let (day, _) = try await store.startDay(at: Date(), plannedStart: nil)
        try await store.append(.recordCaptured(try text(day, Date(), "稳定币研究文档的第三节 plaintext-marker-7f3a")))
        #expect(try await store.records(dayID: day.id).first.map { String(decoding: $0.body, as: UTF8.self) }?.contains("plaintext-marker-7f3a") == true)
        #expect(!(try bytesContain(Data("plaintext-marker-7f3a".utf8), near: url)))
        #expect(!(try bytesContain(Data("稳定币研究文档".utf8), near: url)))
    }

    @Test func missingKeyMeansTheStoreCannotBeOpened() async throws {
        let url = tempURL()
        do {
            let store = try RecordStore(url: url, keys: InMemoryKeyStore())
            let (day, _) = try await store.startDay(at: Date(), plannedStart: nil)
            try await store.append(.recordCaptured(try text(day, Date(), "secret work")))
        }
        // The Keychain item was deleted: opening must fail rather than quietly start over with a new key.
        let empty = InMemoryKeyStore()
        #expect(throws: StoreError.keyMissing) { try RecordStore(url: url, keys: empty) }
        #expect(try empty.load() == nil)
    }

    @Test func wrongKeyCannotRead() async throws {
        let url = tempURL()
        do {
            let store = try RecordStore(url: url, keys: InMemoryKeyStore())
            _ = try await store.startDay(at: Date(), plannedStart: nil)
        }
        try SQLiteConnection(path: url.path).execute("DELETE FROM review_days; DELETE FROM cursors") // force a replay
        let other = InMemoryKeyStore(key: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        #expect(throws: StoreError.wrongKey) { try RecordStore(url: url, keys: other) }
    }

    @Test func plaintextFromAnOlderBuildIsEncryptedOnOpen() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let db = try SQLiteConnection(path: url.path)
            try Schema.migrate(db)
            let day = ReviewDay(startedAt: Date(timeIntervalSince1970: 1_793_400_000))
            try db.run("INSERT INTO events (at, day_id, kind, payload) VALUES (?, ?, 'dayStarted', ?)",
                       [.double(1_793_400_000), .text(day.id.uuidString), .blob(try Event.dayStarted(day).payload())])
            let record = Record(dayID: day.id, at: Date(timeIntervalSince1970: 1_793_400_001), kind: "windowText", body: Data("legacy-plain-9c2e".utf8))
            try db.run("INSERT INTO events (at, day_id, kind, payload) VALUES (?, ?, 'recordCaptured', ?)",
                       [.double(1_793_400_001), .text(day.id.uuidString), .blob(try Event.recordCaptured(record).payload())])
        }
        let store = try RecordStore(url: url, keys: InMemoryKeyStore())
        let day = try #require(try await store.days().first)
        #expect(try await store.records(dayID: day.id).map(\.body) == [Data("legacy-plain-9c2e".utf8)])
        #expect(!(try bytesContain(Data(Data("legacy-plain-9c2e".utf8).base64EncodedString().prefix(12).utf8), near: url)))
        #expect(try await store.verify().isEmpty)
    }
}

@Suite struct RetentionTests {
    let t0 = Date(timeIntervalSince1970: 1_793_400_000)

    @Test func purgeRemovesOnlyOldRecords() async throws {
        let store = try RecordStore(url: tempURL(), keys: testKeys)
        let (old, _) = try await store.startDay(at: t0, plannedStart: nil)
        try await store.append(.recordCaptured(try text(old, t0.addingTimeInterval(60), "old")))
        let later = t0.addingTimeInterval(40 * 86_400)
        let (recent, _) = try await store.startDay(at: later, plannedStart: nil)
        try await store.append(.recordCaptured(try text(recent, later.addingTimeInterval(60), "recent")))

        let removed = try await store.purgeRecords(before: later.addingTimeInterval(-30 * 86_400))
        #expect(removed == 1)
        #expect(try await store.records(dayID: old.id).isEmpty)
        #expect(try await store.records(dayID: recent.id).count == 1)
        #expect(try await store.days().count == 2, "复盘日 survive the purge")
        #expect(try await store.verify().isEmpty)

        try await store.rebuildProjections()
        #expect(try await store.records(dayID: old.id).isEmpty, "a rebuild does not bring purged records back")
    }

    @Test func deletingADayLeavesNoTraceOfItsRecords() async throws {
        let url = tempURL()
        let store = try RecordStore(url: url, keys: testKeys)
        let (day, _) = try await store.startDay(at: t0, plannedStart: nil)
        for i in 0..<20 { try await store.append(.recordCaptured(try text(day, t0.addingTimeInterval(Double(i)), "line \(i)"))) }
        let (today, _) = try await store.startDay(at: t0.addingTimeInterval(86_400), plannedStart: nil)

        // Remember the stored ciphertext so the files can be searched for it afterwards.
        let raw = try SQLiteConnection(path: url.path)
        let stored = try raw.query("SELECT body FROM records WHERE day_id = ?", [.text(day.id.uuidString)]).compactMap { $0.first?.blob }
            + raw.query("SELECT payload FROM events WHERE day_id = ? AND kind = 'recordCaptured'", [.text(day.id.uuidString)]).compactMap { $0.first?.blob }
        #expect(stored.count == 40)

        await #expect(throws: StoreError.dayIsOpen(today.id)) { try await store.deleteDay(today.id, entireDay: false) }
        try await store.deleteDay(day.id, entireDay: false)
        #expect(try await store.records(dayID: day.id).isEmpty)
        #expect(try await store.days().map(\.id).contains(day.id), "the 复盘日 itself is kept")
        for blob in stored {
            #expect(!(try bytesContain(blob.suffix(24), near: url)))
        }

        try await store.deleteDay(day.id, entireDay: true)
        #expect(!(try await store.days().map(\.id).contains(day.id)))
        #expect(try await store.verify().isEmpty)
    }

    @Test func backupIsAConsistentEncryptedCopy() async throws {
        let store = try RecordStore(url: tempURL(), keys: testKeys)
        let (day, _) = try await store.startDay(at: t0, plannedStart: nil)
        try await store.append(.recordCaptured(try text(day, t0.addingTimeInterval(1), "backup-marker-41d0")))
        let copy = tempURL()
        try await store.backup(to: copy)

        #expect(!(try Data(contentsOf: copy).range(of: Data("backup-marker-41d0".utf8)) != nil))
        let restored = try RecordStore(url: copy, keys: testKeys)
        #expect(try await restored.records(dayID: day.id).count == 1)
    }
}
