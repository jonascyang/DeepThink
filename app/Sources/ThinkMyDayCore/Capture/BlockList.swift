import Foundation

/// 不看名单: apps the user does not want recorded. Their windows leave only a placeholder: no title, no text (PRD §6.2).
public struct BlockList: Codable, Sendable, Equatable {
    public struct App: Codable, Sendable, Equatable, Hashable {
        public var bundleID: String
        public var name: String

        public init(bundleID: String, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    public var apps: [App]

    public init(apps: [App]) { self.apps = apps }

    public func contains(_ bundleID: String) -> Bool { apps.contains { $0.bundleID == bundleID } }

    public mutating func add(_ app: App) {
        guard !contains(app.bundleID) else { return }
        apps.append(app)
    }

    public mutating func remove(_ bundleID: String) { apps.removeAll { $0.bundleID == bundleID } }

    /// Password managers, wallets and banks, placed on the list at first launch. The user can remove any of them.
    public static let presets = BlockList(apps: [
        App(bundleID: "com.1password.1password", name: "1Password"),
        App(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
        App(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
        App(bundleID: "com.lastpass.LastPass", name: "LastPass"),
        App(bundleID: "com.dashlane.dashlanephonefinal", name: "Dashlane"),
        App(bundleID: "com.apple.Passwords", name: "密码"),
        App(bundleID: "com.apple.keychainaccess", name: "钥匙串访问"),
        App(bundleID: "com.ledger.live", name: "Ledger Live"),
        App(bundleID: "io.trezor.TrezorSuite", name: "Trezor Suite"),
        App(bundleID: "exodus.desktop", name: "Exodus"),
        App(bundleID: "org.electrum.electrum", name: "Electrum"),
        App(bundleID: "com.sparrowwallet.sparrow", name: "Sparrow"),
        App(bundleID: "cmb.pb", name: "招商银行"),
        App(bundleID: "com.icbc.iphoneclient", name: "中国工商银行"),
        App(bundleID: "com.alipay.iphoneclient", name: "支付宝"),
    ])
}

/// Whether a window may be read. `blocked` follows the user's list; `neverRead` cannot be switched off (PRD §6.2).
public enum ReadDecision: Equatable, Sendable {
    case read
    case blocked
    case neverRead
}

public enum PrivacyRules {
    /// Decides for one window. `browserURL` is the active tab's URL when the window belongs to a browser we can ask.
    public static func decide(bundleID: String, browserURL: String?, incognito: Bool, blockList: BlockList) -> ReadDecision {
        if incognito { return .neverRead }
        // Wallet and password-manager extensions (MetaMask and the like) run as chrome-extension:// pages.
        // Every extension page is skipped: telling wallets apart by extension id would miss new ones.
        if let url = browserURL?.lowercased(), url.hasPrefix("chrome-extension://") || url.hasPrefix("moz-extension://") {
            return .neverRead
        }
        return blockList.contains(bundleID) ? .blocked : .read
    }
}
