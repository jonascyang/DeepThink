import Foundation

public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case system, user, assistant }
    public var role: Role
    public var content: String

    public init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

/// The 对话模型 (PRD §8.4). Implementations hide each provider's differences.
public protocol ChatModel: Sendable {
    func reply(to messages: [ChatMessage]) async throws -> String
}

public enum ChatModelError: Error, Equatable, Sendable, CustomStringConvertible {
    case badURL(String)
    case http(status: Int, body: String)
    case emptyReply
    case unreachable(String)

    public var description: String {
        switch self {
        case .badURL(let s): "模型地址不对：\(s)"
        case .http(let status, let body): "模型返回错误 \(status)：\(body.prefix(300))"
        case .emptyReply: "模型没有返回内容"
        case .unreachable(let s): "连不上模型：\(s)"
        }
    }
}

/// Any server speaking the OpenAI chat completions format, such as magpie on this Mac or Ollama.
/// Records leave the Mac only to this address (PRD §8.5).
public struct OpenAICompatibleModel: ChatModel {
    public var baseURL: String
    public var model: String
    public var apiKey: String?
    public var timeout: TimeInterval
    private let session: URLSession

    public init(baseURL: String, model: String, apiKey: String? = nil, timeout: TimeInterval = 300, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.session = session
    }

    private struct Body: Encodable { let model: String; let messages: [ChatMessage] }
    private struct Response: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
        let choices: [Choice]
    }

    public func reply(to messages: [ChatMessage]) async throws -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/chat/completions"), url.scheme?.hasPrefix("http") == true else {
            throw ChatModelError.badURL(baseURL)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(Body(model: model, messages: messages))
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ChatModelError.unreachable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ChatModelError.http(status: status, body: String(decoding: data, as: UTF8.self)) }
        let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatModelError.emptyReply }
        return content
    }
}
