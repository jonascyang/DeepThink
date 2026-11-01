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

/// Something the user said in a 复盘 and asked to keep: 经验, 自我认识, the plan for tomorrow, or how the day felt.
/// Kept for good, unlike raw records (PRD §10).
public struct ReviewNote: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// 经验: a way of working worth repeating.
        case lesson
        /// 自我认识: something the user learned about themself.
        case selfKnowledge
        /// One item of the plan for tomorrow; `rank` orders them.
        case tomorrow
        /// How the day felt, in one line.
        case mood
    }

    public var id: UUID
    /// The 复盘日 the note was made about.
    public var dayID: UUID
    public var at: Date
    public var kind: Kind
    public var text: String
    /// Position in the plan for tomorrow, 1 first.
    public var rank: Int?

    public init(id: UUID = UUID(), dayID: UUID, at: Date, kind: Kind, text: String, rank: Int? = nil) {
        self.id = id
        self.dayID = dayID
        self.at = at
        self.kind = kind
        self.text = text
        self.rank = rank
    }
}

/// Everything the store persists is an event. The tables the app reads are projections that can be rebuilt from these.
public enum Event: Sendable, Equatable {
    case dayStarted(ReviewDay)
    case dayEnded(dayID: UUID, at: Date)
    case recordCaptured(Record)
    case reviewNoted(ReviewNote)

    var kind: String {
        switch self {
        case .dayStarted: "dayStarted"
        case .dayEnded: "dayEnded"
        case .recordCaptured: "recordCaptured"
        case .reviewNoted: "reviewNoted"
        }
    }

    var at: Date {
        switch self {
        case .dayStarted(let day): day.startedAt
        case .dayEnded(_, let at): at
        case .recordCaptured(let record): record.at
        case .reviewNoted(let note): note.at
        }
    }

    var dayID: UUID {
        switch self {
        case .dayStarted(let day): day.id
        case .dayEnded(let id, _): id
        case .recordCaptured(let record): record.dayID
        case .reviewNoted(let note): note.dayID
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
        case .reviewNoted(let note): try Self.encoder.encode(note)
        }
    }

    init(kind: String, payload: Data) throws {
        switch kind {
        case "dayStarted": self = .dayStarted(try Self.decoder.decode(ReviewDay.self, from: payload))
        case "dayEnded":
            let e = try Self.decoder.decode(DayEnded.self, from: payload)
            self = .dayEnded(dayID: e.dayID, at: e.at)
        case "recordCaptured": self = .recordCaptured(try Self.decoder.decode(Record.self, from: payload))
        case "reviewNoted": self = .reviewNoted(try Self.decoder.decode(ReviewNote.self, from: payload))
        default: throw StoreError.unknownEventKind(kind)
        }
    }
}
