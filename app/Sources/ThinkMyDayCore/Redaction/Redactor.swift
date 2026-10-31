import Foundation

/// Replaces secrets before anything is written to the store (PRD §10). Records are sent to the model as stored,
/// so this is also what keeps secrets from leaving the Mac.
///
/// Errs toward hiding: a bare 64-hex string is treated as a private key even though it may be a transaction hash.
/// Wallet addresses are public and kept.
public enum Redactor {
    public enum Kind: String, CaseIterable, Sendable {
        case privateKey = "私钥"
        case mnemonic = "助记词"
        case jwt = "JWT"
        case apiKey = "API key"
        case secret = "密码或密钥"
        case card = "卡号"

        var placeholder: String { "[已隐去：\(rawValue)]" }
    }

    /// Redacts one piece of text. Lines that belong together (a key block, a mnemonic grid) must be passed together.
    public static func redact(_ text: String) -> String {
        var s = text
        for rule in rules { s = rule.apply(s) }
        s = redactMnemonics(s)
        s = redactCards(s)
        return s
    }

    /// Redacts every string in a JSON document. An array of strings is redacted as one text joined by newlines,
    /// so a key or mnemonic split across lines is still caught.
    /// A body that is not JSON is redacted as UTF-8 text.
    public static func redactJSON(_ data: Data) throws -> Data {
        if data.isEmpty { return data }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return Data(redact(String(decoding: data, as: UTF8.self)).utf8)
        }
        return try JSONSerialization.data(withJSONObject: walk(object), options: [.fragmentsAllowed, .sortedKeys])
    }

    private static func walk(_ value: Any) -> Any {
        switch value {
        case let s as String:
            return redact(s)
        case let array as [Any]:
            if !array.isEmpty, let strings = array as? [String] {
                return redact(strings.joined(separator: "\n")).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            }
            return array.map(walk)
        case let dict as [String: Any]:
            return dict.mapValues(walk)
        default:
            return value
        }
    }

    // MARK: - Pattern rules

    private struct Rule {
        let regex: NSRegularExpression
        let template: String

        init(_ pattern: String, _ template: String) {
            regex = try! NSRegularExpression(pattern: pattern, options: [])
            self.template = template
        }

        func apply(_ s: String) -> String {
            regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
    }

    private static let base58 = "[1-9A-HJ-NP-Za-km-z]"

    private static let rules: [Rule] = [
        // PEM private keys, also when only the start of the block is on screen.
        Rule(#"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----(?:\s*[A-Za-z0-9+/=]{8,})*(?:\s*-----END [A-Z0-9 ]*PRIVATE KEY-----)?"#,
             Kind.privateKey.placeholder),
        Rule(#"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, Kind.jwt.placeholder),
        // Provider keys with a recognisable prefix.
        Rule(#"\b(?:sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}|sk_(?:live|test)_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,}"#
             + #"|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{20,}"#
             + #"|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[abposr]-[A-Za-z0-9-]{10,}"#
             + #"|hf_[A-Za-z0-9]{30,}|npm_[A-Za-z0-9]{36}|pypi-[A-Za-z0-9_-]{50,})"#, Kind.apiKey.placeholder),
        Rule(#"(?i)(\bbearer\s+)[A-Za-z0-9._~+/-]{16,}=*"#, "$1" + Kind.apiKey.placeholder),
        // key = value, key: "value"
        Rule(#"(?i)((?:(?<![A-Za-z0-9])(?:api[_-]?key|secret(?:[_-]?key)?|access[_-]?key(?:[_-]?id)?|private[_-]?key|client[_-]?secret|auth[_-]?token|access[_-]?token|token|password|passwd|pwd)(?![A-Za-z0-9])|密码|口令|密钥)["']?\s*[:=：]\s*["']?)[^\s"',;]{6,}"#,
             "$1" + Kind.secret.placeholder),
        // Raw private keys: 64 hex digits (Ethereum and most chains), WIF, extended private keys.
        Rule(#"(?<![0-9A-Za-z])(?:0x)?[0-9a-fA-F]{64}(?![0-9A-Za-z])"#, Kind.privateKey.placeholder),
        Rule(#"(?<![0-9A-Za-z])[5KL]\#(base58){50,51}(?![0-9A-Za-z])"#, Kind.privateKey.placeholder),
        Rule(#"(?<![0-9A-Za-z])[xyzt]prv\#(base58){100,}(?![0-9A-Za-z])"#, Kind.privateKey.placeholder),
        // URLs keep their path; query and fragment can carry tokens.
        Rule(#"(https?://[^\s?#"'<>]+)[?#][^\s"'<>]*"#, "$1"),
    ]

    // MARK: - Mnemonics

    /// Twelve or more BIP39 words in a row, English or simplified Chinese, separated only by spaces,
    /// line breaks or the numbering a wallet shows next to each word.
    static func redactMnemonics(_ s: String) -> String {
        var ranges: [Range<String.Index>] = []
        var run: [Range<String.Index>] = []

        func close() {
            if run.count >= 12, let first = run.first, let last = run.last { ranges.append(first.lowerBound..<last.upperBound) }
            run = []
        }

        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isASCII, c.isLetter {
                var j = i
                while j < s.endIndex, s[j].isASCII, s[j].isLetter { j = s.index(after: j) }
                if BIP39Words.english.contains(s[i..<j].lowercased()[...]) { run.append(i..<j) } else { close() }
                i = j
            } else if BIP39Words.chineseSimplified.contains(c) {
                // A Chinese word only counts when it stands alone; ordinary prose runs characters together.
                let next = s.index(after: i)
                let alone = (i == s.startIndex || !isHan(s[s.index(before: i)])) && (next == s.endIndex || !isHan(s[next]))
                if alone { run.append(i..<next) } else { close() }
                i = next
            } else if c.isWhitespace || c.isNumber || ".)、:：".contains(c) {
                i = s.index(after: i)
            } else {
                close()
                i = s.index(after: i)
            }
        }
        close()

        var out = s
        for r in ranges.reversed() { out.replaceSubrange(r, with: Kind.mnemonic.placeholder) }
        return out
    }

    private static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    // MARK: - Cards

    private static let cardCandidate = try! NSRegularExpression(pattern: #"(?<![0-9])[2-6](?:[ -]?[0-9]){12,18}(?![0-9])"#)

    /// 13–19 digits, optionally grouped by spaces or dashes, that pass the Luhn check.
    static func redactCards(_ s: String) -> String {
        let ns = s as NSString
        var out = s
        for match in cardCandidate.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let digits = ns.substring(with: match.range).filter(\.isNumber)
            guard (13...19).contains(digits.count), luhn(digits), let r = Range(match.range, in: out) else { continue }
            out.replaceSubrange(r, with: Kind.card.placeholder)
        }
        return out
    }

    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard var d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
        }
        return sum % 10 == 0
    }
}

extension Record {
    /// The record with every secret in its body replaced.
    public func redacted() throws -> Record {
        var copy = self
        copy.body = try Redactor.redactJSON(body)
        return copy
    }
}
