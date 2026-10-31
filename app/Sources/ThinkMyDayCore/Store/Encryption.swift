import CryptoKit
import Foundation
import Security

/// Where the database key lives. The app uses the Keychain; tests and development tools supply their own.
public protocol KeyStore: Sendable {
    func load() throws -> Data?
    func save(_ key: Data) throws
}

/// The login Keychain, as a generic password readable only on this Mac after first unlock.
public struct KeychainKeyStore: KeyStore {
    public let service: String
    public let account: String

    public init(service: String = "com.jonascyang.thinkmyday", account: String = "database-key") {
        self.service = service
        self.account = account
    }

    public func load() throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw StoreError.keychain(status)
        }
    }

    public func save(_ key: Data) throws {
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecValueData: key, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrLabel: "Think My Day 记录库密钥",
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }
}

/// A key kept in memory, for tests.
public final class InMemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?

    public init(key: Data? = nil) { self.key = key }

    public func load() throws -> Data? { lock.withLock { key } }
    public func save(_ key: Data) throws { lock.withLock { self.key = key } }
}

/// AES-256-GCM over every stored payload. Encrypted values start with a marker so plaintext from an
/// older build can be told apart and encrypted on open.
struct PayloadCipher: Sendable {
    static let marker = Data("TMDE1".utf8)
    let key: SymmetricKey

    func seal(_ plaintext: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else { throw StoreError.encryptionFailed }
        return Self.marker + combined
    }

    func open(_ stored: Data) throws -> Data {
        guard Self.isSealed(stored) else { return stored }
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: stored.dropFirst(Self.marker.count)), using: key)
        } catch {
            throw StoreError.wrongKey
        }
    }

    static func isSealed(_ data: Data) -> Bool { data.starts(with: marker) }

    /// Loads the key, creating one only for a database that holds nothing encrypted yet.
    static func load(from keys: KeyStore, databaseHasSealedData: Bool) throws -> PayloadCipher {
        if let raw = try keys.load() { return PayloadCipher(key: SymmetricKey(data: raw)) }
        // Making a new key here would hide the loss: the old data could never be read again.
        guard !databaseHasSealedData else { throw StoreError.keyMissing }
        let key = SymmetricKey(size: .bits256)
        try keys.save(key.withUnsafeBytes { Data($0) })
        return PayloadCipher(key: key)
    }
}
