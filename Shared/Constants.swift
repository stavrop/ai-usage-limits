import Foundation

/// App-wide identifiers shared by the app and the widget extension.
///
/// Per-provider endpoints, client ids and scopes live with their provider in
/// `Shared/Providers/`, not here.
enum Config {
    // These match the XcodeGen project (project.yml) and the .entitlements files.
    /// Shares the cached usage snapshots between app and widget.
    static let appGroup = "group.com.stavrop.ailimits"
    /// Shares credentials with the widget. Must include the team-id
    /// (AppIdentifierPrefix) prefix: "<TeamID>.<group>".
    static let keychainAccessGroup = "NCZ7646BF7.com.stavrop.ailimits.shared"
    static let keychainService = "AIUsageLimits"

    /// Several token hosts sit behind Cloudflare, which answers unrecognised
    /// clients with HTTP 403 "error code: 1010" before the endpoint is reached.
    static let userAgent = "AIUsageLimits/0.3.0 (iOS; +https://github.com/stavrop/ai-usage-monitor)"
}

/// User preferences, stored in the App Group so the widget sees them too.
enum Settings {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: Config.appGroup) ?? .standard
    }

    private enum Key {
        static let hasOnboarded = "hasOnboarded"
        static let pollMinutes = "pollMinutes"
        static let alertThreshold = "alertThreshold"
    }

    /// Set once the user finishes (or skips past) onboarding.
    static var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    /// Foreground refresh cadence. Clamped 1–120 to match the macOS app.
    static var pollMinutes: Int {
        get {
            let stored = defaults.integer(forKey: Key.pollMinutes)
            return stored == 0 ? 10 : min(max(stored, 1), 120)
        }
        set { defaults.set(min(max(newValue, 1), 120), forKey: Key.pollMinutes) }
    }

    /// Percentage at which a bucket is highlighted as nearly spent.
    static var alertThreshold: Int {
        get {
            let stored = defaults.integer(forKey: Key.alertThreshold)
            return stored == 0 ? 85 : min(max(stored, 1), 100)
        }
        set { defaults.set(min(max(newValue, 1), 100), forKey: Key.alertThreshold) }
    }

    /// Wipes everything a disconnect should remove for one provider.
    static func forget(_ provider: ProviderID) {
        CredentialStore.clear(provider)
        UsageCache.remove(provider)
    }

    /// Erases every trace of the user: all credentials, all cached readings, and
    /// all preferences — returning the app to a fresh install.
    ///
    /// Onboarding is reset too, so the next launch explains what the app does
    /// before asking for anything again.
    static func eraseEverything() {
        CredentialStore.clearAll()
        UsageCache.clearAll()
        for key in [Key.hasOnboarded, Key.pollMinutes, Key.alertThreshold] {
            defaults.removeObject(forKey: key)
        }
    }
}
