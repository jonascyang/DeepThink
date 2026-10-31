import Foundation
import ThinkMyDayCore

// Development tool for scripts/crash-test.sh.
//   tmd-store-stress write <db>   appends records until killed
//   tmd-store-stress verify <db>  exits 1 if the database is damaged or a record is incomplete
//   tmd-store-stress dump <db>    one line per record: kind, app, whether it has a title and how many lines; never the text
// The key is read from <db>.key, so this never touches the Keychain (a scratch app store under $TMD_DATA_DIR uses the same file).

let args = CommandLine.arguments
guard args.count == 3, ["write", "verify", "dump"].contains(args[1]) else {
    FileHandle.standardError.write(Data("usage: tmd-store-stress write|verify|dump <db>\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: args[2])

/// Each record body repeats its own sequence number, so a torn write would show up as a mismatch.
func body(_ n: Int) -> Data { Data(String(repeating: "\(n)|", count: 200).utf8) }

let store = try RecordStore(url: url, keys: FileKeyStore(file: url.appendingPathExtension("key")))
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
case "dump":
    for day in try await store.days() {
        for record in try await store.records(dayID: day.id) {
            let json = (try? JSONSerialization.jsonObject(with: record.body)) as? [String: Any] ?? [:]
            let app = json["bundleID"] as? String ?? "-"
            let title = (json["title"] as? String).map { $0.isEmpty ? "empty" : "title" } ?? "no-title"
            let lines = (json["added"] as? [Any])?.count ?? 0
            let extra = [json["reason"], json["hidden"], json["state"]].compactMap { $0 as? String }.joined(separator: ",")
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
