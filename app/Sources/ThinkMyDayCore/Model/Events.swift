import Foundation

/// A 复盘日: from 开启一天 until 结束一天 (or the next 开启一天 when the user forgets to end it).
public struct ReviewDay: Codable, Sendable, Equatable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    /// The 计划开始时刻 this day is compared against, resolved to an absolute time when the day started.
    public var plannedStart: Date?

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil, plannedStart: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedStart = plannedStart
    }
}

/// A 记录: one observed fact. `kind` and `body` are left open here; the capture issues (#6–#8) give them shape.
public struct Record: Codable, Sendable, Equatable {
    public var id: UUID
    public var dayID: UUID
    public var at: Date
    public var kind: String
    public var body: Data

    public init(id: UUID = UUID(), dayID: UUID, at: Date, kind: String, body: Data) {
        self.id = id
        self.dayID = dayID
        self.at = at
        self.kind = kind
        self.body = body
    }
}

/// Everything the store persists is an event. The tables the app reads are projections that can be rebuilt from these.
public enum Event: Sendable, Equatable {
    case dayStarted(ReviewDay)
    case dayEnded(dayID: UUID, at: Date)
    case recordCaptured(Record)

    var kind: String {
        switch self {
        case .dayStarted: "dayStarted"
        case .dayEnded: "dayEnded"
        case .recordCaptured: "recordCaptured"
        }
    }

    var at: Date {
        switch self {
        case .dayStarted(let day): day.startedAt
        case .dayEnded(_, let at): at
        case .recordCaptured(let record): record.at
        }
    }

    var dayID: UUID {
        switch self {
        case .dayStarted(let day): day.id
        case .dayEnded(let id, _): id
        case .recordCaptured(let record): record.dayID
        }
    }
}

extension Event {
    private struct DayEnded: Codable { var dayID: UUID; var at: Date }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = .sortedKeys
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    func payload() throws -> Data {
        switch self {
        case .dayStarted(let day): try Self.encoder.encode(day)
        case .dayEnded(let id, let at): try Self.encoder.encode(DayEnded(dayID: id, at: at))
        case .recordCaptured(let record): try Self.encoder.encode(record)
        }
    }

    init(kind: String, payload: Data) throws {
        switch kind {
        case "dayStarted": self = .dayStarted(try Self.decoder.decode(ReviewDay.self, from: payload))
        case "dayEnded":
            let e = try Self.decoder.decode(DayEnded.self, from: payload)
            self = .dayEnded(dayID: e.dayID, at: e.at)
        case "recordCaptured": self = .recordCaptured(try Self.decoder.decode(Record.self, from: payload))
        default: throw StoreError.unknownEventKind(kind)
        }
    }
}
