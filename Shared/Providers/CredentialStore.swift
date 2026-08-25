import Foundation

/// Credentials for one provider. OAuth providers fill the token fields; API-key
/// providers fill `apiKey`.
struct Credential: Codable, Sendable {
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?
    /// The scope actually GRANTED, echoed back by the token endpoint. Refreshes
    /// must replay this exact string — replaying what we requested is rejected.
    var scope: String?
    var apiKey: String?
    /// Provider-specific extras (e.g. ChatGPT's account id header value).
    var extras: [String: String]?
    var accountLabel: String?

    /// Refresh a little early so a request that starts just before expiry can't
    /// race the deadline.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt.addingTimeInterval(-300)
    }

    var isPresent: Bool {
        (accessToken?.isEmpty == false) || (apiKey?.isEmpty == false)
    }
}

/// Per-provider Keychain storage, in a shared access group so the widget can read
/// it too.
///
/// One item per provider (account = the ProviderID raw value), so connecting or
/// disconnecting one service never disturbs another.
enum CredentialStore {

    private static func baseQuery(_ provider: ProviderID) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.keychainService,
            kSecAttrAccount as String: provider.rawValue,
        ]
        // Access groups need a real provisioning profile, which the Simulator
        // doesn't have — including it there makes every Keychain call fail. On a
        // device it's required so the app and widget share credentials.
        #if !targetEnvironment(simulator)
        q[kSecAttrAccessGroup as String] = Config.keychainAccessGroup
        #endif
        return q
    }

    static func save(_ credential: Credential, for provider: ProviderID) {
        guard let data = try? JSONEncoder().encode(credential) else { return }
        var query = baseQuery(provider)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(_ provider: ProviderID) -> Credential? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let credential = try? JSONDecoder().decode(Credential.self, from: data) else {
            return nil
        }
        return credential
    }

    static func clear(_ provider: ProviderID) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
    }

    static func isConnected(_ provider: ProviderID) -> Bool {
        load(provider)?.isPresent ?? false
    }

    /// Removes every credential this app has stored, for every provider.
    ///
    /// Deletes by provider AND sweeps the whole service, so items written by an
    /// older build (which used a single "tokens" account) are removed too — a
    /// "delete everything" control that leaves orphans behind is worse than none.
    static func clearAll() {
        for provider in ProviderID.allCases { clear(provider) }

        var sweep: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.keychainService,
        ]
        #if !targetEnvironment(simulator)
        sweep[kSecAttrAccessGroup as String] = Config.keychainAccessGroup
        #endif
        SecItemDelete(sweep as CFDictionary)
    }

    /// Providers the user has actually connected, in display order.
    static var connectedProviders: [ProviderID] {
        ProviderID.displayOrder.filter { isConnected($0) }
    }
}

/// Last successful reading per provider, shared with the widget through the App
/// Group so a widget can render instantly and offline.
enum UsageCache {
    private static let key = "usageByProvider.v2"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: Config.appGroup)
    }

    static func save(_ usage: ProviderUsage) {
        var all = loadAll()
        all[usage.provider] = usage
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults?.set(data, forKey: key)
    }

    static func loadAll() -> [ProviderID: ProviderUsage] {
        guard let data = defaults?.data(forKey: key),
              let all = try? JSONDecoder().decode([ProviderID: ProviderUsage].self, from: data) else {
            return [:]
        }
        return all
    }

    static func load(_ provider: ProviderID) -> ProviderUsage? {
        loadAll()[provider]
    }

    static func remove(_ provider: ProviderID) {
        var all = loadAll()
        all[provider] = nil
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults?.set(data, forKey: key)
    }

    /// Drops every cached reading, including any written by an older build.
    static func clearAll() {
        defaults?.removeObject(forKey: key)
        defaults?.removeObject(forKey: "lastUsageSnapshot")   // pre-multi-provider
    }
}
