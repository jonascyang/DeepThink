import Foundation
import ThinkMyDayCore

// Development tool for scripts/crash-test.sh.
//   tmd-store-stress write <db>   appends records until killed
//   tmd-store-stress verify <db>  exits 1 if the database is damaged or a record is incomplete
//   tmd-store-stress dump <db>    one line per record: kind, app, whether it has a title and how many lines; never the text
//   tmd-store-stress find <db> <text>  how many records contain <text>, and in which kinds; never the text itself
//   tmd-store-stress jsonl <db>   every 复盘日 and record, decrypted, one JSON object per line on stdout (contains the text)
//   tmd-store-stress digest <db>  the latest day with records as the 复盘 model reads it (contains the text)
//   tmd-store-stress review <db> <base-url> <model>  sends that digest with the opening message and prints the reply
// The key is read from <db>.key, so this never touches the Keychain (a scratch app store under $TMD_DATA_DIR uses the same file).
// With TMD_KEYCHAIN=1 it uses the app's Keychain key instead, to check the real store; macOS asks first.

let args = CommandLine.arguments
guard args.count >= 3, ["write", "verify", "dump", "find", "jsonl", "digest", "review"].contains(args[1]), args[1] != "find" || args.count == 4,
      args[1] != "review" || args.count == 5 else {
    FileHandle.standardError.write(Data("usage: tmd-store-stress write|verify|dump|jsonl|digest <db> | find <db> <text> | review <db> <base-url> <model>\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: args[2])

/// Each record body repeats its own sequence number, so a torn write would show up as a mismatch.
func body(_ n: Int) -> Data { Data(String(repeating: "\(n)|", count: 200).utf8) }

let keys: KeyStore = ProcessInfo.processInfo.environment["TMD_KEYCHAIN"] == "1"
    ? KeychainKeyStore() : FileKeyStore(file: url.appendingPathExtension("key"))
let store = try RecordStore(url: url, keys: keys)
switch args[1] {
case "write":
    let day: ReviewDay
    if let open = try await store.openDay() {
        day = open
    } else {
        day = ReviewDay(startedAt: Date())
        try await store.append(.dayStarted(day))
    }
    var n = try await store.records(dayID: day.id).count
    while true {
        try await store.append(.recordCaptured(Record(dayID: day.id, at: Date(), kind: "stress", body: body(n))))
        n += 1
    }
case "find":
    let needle = args[3]
    var kinds: [String: Int] = [:]
    for day in try await store.days() {
        for record in try await store.records(dayID: day.id) where String(decoding: record.body, as: UTF8.self).contains(needle) {
            kinds[record.kind, default: 0] += 1
        }
    }
    print(kinds.isEmpty ? "not found" : kinds.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
case "jsonl":
    func line(_ object: [String: Any]) throws {
        print(String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self))
    }
    for day in try await store.days() {
        try line(["type": "day", "id": day.id.uuidString, "startedAt": day.startedAt.timeIntervalSince1970,
                  "endedAt": day.endedAt?.timeIntervalSince1970 ?? NSNull(), "plannedStart": day.plannedStart?.timeIntervalSince1970 ?? NSNull()])
        for record in try await store.records(dayID: day.id) {
            let body = (try? JSONSerialization.jsonObject(with: record.body)) ?? String(decoding: record.body, as: UTF8.self)
            try line(["type": "record", "id": record.id.uuidString, "dayID": day.id.uuidString, "at": record.at.timeIntervalSince1970,
                      "kind": record.kind, "body": body])
        }
    }
case "digest", "review":
    var latest: (ReviewDay, [Record])?
    for day in try await store.days() {
        let records = try await store.records(dayID: day.id)
        if !records.isEmpty { latest = (day, records) }
    }
    guard let (day, records) = latest else { print("no records"); exit(1) }
    let digest = DayDigest.make(day: day, records: records)
    if args[1] == "digest" { print(digest); exit(0) }
    let system = ReviewPrompt.system(direction: "遇到难题能自己拆开、想清楚，不再逃；稳定推进手上的几条主线", notes: try await store.notes(), digest: digest)
    let started = Date()
    let reply = try await OpenAICompatibleModel(baseURL: args[3], model: args[4]).reply(to: [ChatMessage(.system, system), ChatMessage(.user, ReviewPrompt.opening)])
    print("[\(Int(Date().timeIntervalSince(started))) s, prompt \(system.count) chars]")
    print(reply)
    print("---- parsed ----")
    let parsed = ReviewReply.parse(reply)
    print(parsed.text)
    for line in parsed.workList?.lines ?? [] { print("•", line.title, "|", line.status, "|", line.result, "|", line.minutes ?? -1) }
    print("other:", parsed.workList?.other ?? "-", "options:", parsed.options)
case "dump":
    for day in try await store.days() {
        for record in try await store.records(dayID: day.id) {
            let json = (try? JSONSerialization.jsonObject(with: record.body)) as? [String: Any] ?? [:]
            let app = json["bundleID"] as? String ?? "-"
            let title = (json["title"] as? String).map { $0.isEmpty ? "empty" : "title" } ?? "no-title"
            let lines = (json["added"] as? [Any])?.count ?? 0
            var extra = [json["reason"], json["hidden"], json["state"]].compactMap { $0 as? String }.joined(separator: ",")
            if let windows = json["windows"] as? [[String: Any]], let screens = json["screens"] as? [Any] {
                extra = "screens \(screens.count) windows \(windows.count) on " + windows.map { "\($0["screen"] ?? "?")" }.joined(separator: "/")
            }
            print(record.kind, app, title, lines, extra)
        }
    }
default:
    var problems = try await store.verify()
    var count = 0
    for day in try await store.days() {
        for (i, record) in try await store.records(dayID: day.id).enumerated() {
            if record.body != body(i) { problems.append("record \(i) of day \(day.id) is incomplete") }
            count += 1
        }
    }
    print(problems.isEmpty ? "ok \(count) records" : problems.joined(separator: "\n"))
    exit(problems.isEmpty ? 0 : 1)
}
