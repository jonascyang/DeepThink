import Foundation
import ThinkMyDayCore

// Development tool for scripts/crash-test.sh.
//   tmd-store-stress write <db>   appends records until killed
//   tmd-store-stress verify <db>  exits 1 if the database is damaged or a record is incomplete

let args = CommandLine.arguments
guard args.count == 3, ["write", "verify"].contains(args[1]) else {
    FileHandle.standardError.write(Data("usage: tmd-store-stress write|verify <db>\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: args[2])

/// Each record body repeats its own sequence number, so a torn write would show up as a mismatch.
func body(_ n: Int) -> Data { Data(String(repeating: "\(n)|", count: 200).utf8) }

let store = try RecordStore(url: url)
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
