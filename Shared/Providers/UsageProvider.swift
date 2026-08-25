import Foundation

/// How a provider is connected.
enum AuthKind: Sendable {
    /// Browser sign-in: PKCE authorization code caught by an on-device loopback
    /// listener. `fixedPort` is non-nil when the provider registered an exact
    /// redirect (OpenAI pins 1455); nil means any high port is accepted.
    case oauth(OAuthConfig)
    /// The user pastes a key from the provider's dashboard.
    case apiKey(APIKeyConfig)
    /// The user approves in the provider's web page, and the app polls a
    /// endpoint until a token is issued. Cursor works this way — there is no
    /// redirect back, so there is nothing for a loopback listener to catch.
    case browserPoll(BrowserPollConfig)
}

struct OAuthConfig: Sendable {
    var clientID: String
    var authorizeURL: String
    var tokenURL: String
    var scopes: String
    var fixedPort: UInt16?
    var callbackPath: String
    /// Extra query items some providers require on /authorize.
    var extraAuthorizeItems: [String: String]
    /// Sent on the code exchange only (Claude wants anthropic-beta there).
    var exchangeHeaders: [String: String]
    var userAgent: String?
}

struct BrowserPollConfig: Sendable {
    /// Seconds between polls.
    var interval: TimeInterval
    /// Give up after this long, so a user who closes the page isn't left hanging.
    var timeout: TimeInterval
}

struct APIKeyConfig: Sendable {
    /// Shown above the text field.
    var instructions: String
    /// Where to get one.
    var dashboardURL: String
    var placeholder: String
}

/// Anything that can report usage.
///
/// Each provider owns its own credential handling and parsing; the app only ever
/// sees `ProviderUsage`. Adding a provider means conforming here and adding a
/// case to `ProviderID` — nothing else in the app changes.
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var auth: AuthKind { get }

    /// Fetch current usage. `allowRefresh` is false in the widget, which must not
    /// rotate tokens behind the app's back.
    func fetchUsage(allowRefresh: Bool) async throws -> ProviderUsage
}

extension UsageProvider {
    var isOAuth: Bool { if case .oauth = auth { return true }; return false }
}

/// Errors surfaced to the UI. One vocabulary for every provider.
enum ProviderError: Error, LocalizedError, Equatable {
    case notConnected
    case sessionExpired
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected"
        case .sessionExpired:
            return "Session expired — connect again"
        case .unauthorized:
            return "Credentials were rejected"
        case .rateLimited(let retry):
            if let retry {
                return "Rate limited — retry in \(Int(retry))s"
            }
            return "Rate limited by the provider"
        case .badResponse(let detail):
            return detail
        case .network(let detail):
            return detail
        }
    }

    /// True when the only cure is reconnecting.
    var needsReconnect: Bool {
        self == .notConnected || self == .sessionExpired || self == .unauthorized
    }
}

/// Every provider the app knows about.
enum ProviderRegistry {
    static let all: [any UsageProvider] = [
        AnthropicProvider(),
        OpenAIProvider(),
        GrokProvider(),
        CursorProvider(),
        OpenRouterProvider(),
    ]

    static func provider(_ id: ProviderID) -> any UsageProvider {
        all.first { $0.id == id } ?? AnthropicProvider()
    }
}
