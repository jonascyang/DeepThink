import Foundation
import Testing
@testable import ThinkMyDayCore

/// Fake secrets in the shape of real ones. None of them is a live credential.
/// Provider prefixes are joined at run time so secret scanners do not flag this file.
enum Secrets {
    private static func token(_ parts: String...) -> String { parts.joined() }

    static let pem = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACDfakefakefakefakefakefakefakefakefakefakefakefakeAAAAAAAA
    -----END OPENSSH PRIVATE KEY-----
    """
    static let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    static let openAI = token("sk-", "proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789")
    static let anthropic = token("sk-", "ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-abc")
    static let github = token("gh", "p_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789")
    static let aws = token("AK", "IAIOSFODNN7EXAMPLE")
    static let google = token("AI", "zaSyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q")
    static let slack = token("xo", "xb-123456789012-abcdefghijklmnop")
    static let stripe = token("sk_", "live_AbCdEfGhIjKlMnOpQrSt")
    static let ethKey = "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
    static let wif = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
    static let mnemonic = "abandon ability able about above absent absorb abstract absurd abuse access accident"
    static let numberedMnemonic = "1. legal 2. winner 3. thank 4. year 5. wave 6. sausage\n7. worth 8. useful 9. legal 10. winner 11. thank 12. yellow"
    static let chineseMnemonic = "的 一 是 在 不 了 有 和 人 这 中 大"
    static let card = "4111 1111 1111 1111"
    static let password = "hunter2-correct-horse"

    /// A bare password looks like any other word; only one labelled as a password can be recognised.
    /// Password fields themselves are never read (#6).
    static let all = [pem, jwt, openAI, anthropic, github, aws, google, slack, stripe, ethKey, wif, mnemonic,
                      numberedMnemonic, chineseMnemonic, card, "password=\(password)", "密码：\(password)"]
    /// A piece of each secret that must not survive, even partially.
    static let fingerprints = ["b3BlbnNzaC1rZXktdjEAAAAABG5vbmU", "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV", "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789",
                               aws, google, String(slack.suffix(16)), String(ethKey.dropFirst(2)), wif,
                               "absorb abstract absurd", "sausage", "的 一 是 在 不 了", "4111 1111 1111 1111", "hunter2-correct-horse"]
}

@Suite struct RedactorTests {
    @Test(arguments: [
        (Secrets.pem, "私钥"), (Secrets.jwt, "JWT"), (Secrets.openAI, "API key"), (Secrets.anthropic, "API key"),
        (Secrets.github, "API key"), (Secrets.aws, "API key"), (Secrets.google, "API key"), (Secrets.slack, "API key"),
        (Secrets.stripe, "API key"), (Secrets.ethKey, "私钥"), (Secrets.wif, "私钥"), (Secrets.mnemonic, "助记词"),
        (Secrets.numberedMnemonic, "助记词"), (Secrets.chineseMnemonic, "助记词"), (Secrets.card, "卡号"),
        ("4111-1111-1111-1111", "卡号"), ("4111111111111111", "卡号"),
    ])
    func hidesSecret(secret: String, kind: String) {
        // Neighbours that are not BIP39 words, so a mnemonic run cannot swallow them.
        let out = Redactor.redact("前文 \(secret) 后文")
        #expect(out.contains("[已隐去：\(kind)]"))
        #expect(out.hasPrefix("前文 ") && out.hasSuffix(" 后文"))
    }

    @Test func hidesValuesOfSecretAssignments() {
        #expect(Redactor.redact("OPENAI_API_KEY=abc123def456ghi") == "OPENAI_API_KEY=[已隐去：密码或密钥]")
        #expect(Redactor.redact(#"password: "\#(Secrets.password)""#) == #"password: "[已隐去：密码或密钥]""#)
        #expect(Redactor.redact("密码：Abc12345!") == "密码：[已隐去：密码或密钥]")
        #expect(Redactor.redact("Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345") == "Authorization: Bearer [已隐去：API key]")
    }

    @Test func urlsLoseQueryAndFragment() {
        #expect(Redactor.redact("see https://example.com/reset?token=abc&u=1#x now") == "see https://example.com/reset now")
    }

    @Test func pemSplitAcrossJSONArrayLinesIsCaught() throws {
        let body = try JSONSerialization.data(withJSONObject: ["added": Secrets.pem.components(separatedBy: "\n") + ["next line"]])
        let out = String(decoding: try Redactor.redactJSON(body), as: UTF8.self)
        #expect(!out.contains("b3BlbnNzaC1rZXktdjEAAAAABG5vbmU"))
        #expect(out.contains("next line"))
    }

    // MARK: - Things that must stay

    @Test(arguments: [
        "今天和产品经理讨论了稳定币的发行计划，下午写研究文档。",
        "The quick brown fox jumps over the lazy dog while the team reviews the stablecoin draft.",
        "let total = items.map { $0.price }.reduce(0, +) // sum prices",
        "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",            // Ethereum address
        "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",           // Bitcoin address
        "TQn9Y2khEsLJW1ChVWFMSMeRDow5KcbLSE",                   // Tron address
        "订单号 20261031 金额 1234.56 元，电话 13800138000",
        "commit 3f2a9c1 fixes the build; see PR 1234",
        "abandon the plan, ability matters more than luck",      // BIP39 words, but far fewer than twelve in a row
        "https://example.com/docs/page",
        "token count: 1,234",
    ])
    func keepsOrdinaryText(_ text: String) {
        #expect(Redactor.redact(text) == text)
    }

    @Test func luhn() {
        #expect(Redactor.luhn("4111111111111111"))
        #expect(!Redactor.luhn("4111111111111112"))
    }

    @Test func wordlistsAreComplete() {
        #expect(BIP39Words.english.count == 2048)
        #expect(BIP39Words.chineseSimplified.count == 2048)
    }

    @Test func redactedRecordStillDecodes() throws {
        let body = WindowText(windowID: 1, bundleID: "com.apple.Terminal", appName: "终端", title: "export \(Secrets.openAI)",
                              focused: true, method: .accessibility, url: "https://x.com/a?b=c", added: ["key \(Secrets.github)", "ok"],
                              lineCount: 2, visibleChars: 40, truncated: false)
        let record = try Record(dayID: UUID(), at: Date(timeIntervalSince1970: 1_793_400_000.25), kind: .windowText, body: body).redacted()
        let decoded = try record.decode(WindowText.self)
        #expect(decoded.title == "export [已隐去：API key]")
        #expect(decoded.added == ["key [已隐去：API key]", "ok"])
        #expect(decoded.url == "https://x.com/a")
        #expect(decoded.focused)
    }
}

@Suite struct RedactedStoreTests {
    /// Red-team case from #9: after writing every secret, no byte of the database, WAL or shared memory holds it.
    @Test func storeFilesHoldNoSecret() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tmd-tests-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("thinkmyday.sqlite")
        let store = try RecordStore(url: url)
        let (day, _) = try await store.startDay(at: Date(), plannedStart: nil)
        for (i, secret) in Secrets.all.enumerated() {
            let body = WindowText(windowID: UInt32(i), bundleID: "test", appName: "test", title: secret, focused: true,
                                  method: .accessibility, added: secret.components(separatedBy: "\n"), lineCount: 1, visibleChars: 1, truncated: false)
            try await store.append(.recordCaptured(try Record(dayID: day.id, at: Date(), kind: .windowText, body: body)))
            try await store.append(.recordCaptured(try Record(dayID: day.id, at: Date(), kind: .focus,
                                                                body: Focus(windowID: nil, bundleID: "test", appName: "test", title: secret))))
        }

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.lastPathComponent.hasSuffix("-wal") })
        for file in files {
            let bytes = try Data(contentsOf: file)
            for fingerprint in Secrets.fingerprints {
                #expect(bytes.range(of: Data(fingerprint.utf8)) == nil, "\(fingerprint) found in \(file.lastPathComponent)")
                // Events keep the record body as base64 inside their JSON payload.
                #expect(bytes.range(of: Data(Data(fingerprint.utf8).base64EncodedString().prefix(16).utf8)) == nil,
                        "\(fingerprint) found base64-encoded in \(file.lastPathComponent)")
            }
        }
    }
}
