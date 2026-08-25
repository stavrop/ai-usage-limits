import Foundation
import CryptoKit

/// Cursor.
///
/// Cursor's CLI uses a deep-link approval rather than a redirect: it opens
/// `cursor.com/loginDeepControl?challenge=…&uuid=…`, the user taps "Yes, Log In",
/// and the client polls `api2.cursor.sh/auth/poll` until a token is issued. There
/// is no redirect back, so there is nothing for a loopback listener to catch —
/// hence `AuthKind.browserPoll`.
///
/// Everything here is reverse-engineered from Cursor's own client and is the
/// least certain provider in the app; expect to adjust on first contact.
struct CursorProvider: UsageProvider {
    let id: ProviderID = .cursor

    static let loginURL = "https://cursor.com/loginDeepControl"
    static let pollURL = "https://api2.cursor.sh/auth/poll"
    static let usageURL = "https://cursor.com/api/usage-summary"
    static let meURL = "https://cursor.com/api/auth/me"

    var auth: AuthKind {
        .browserPoll(BrowserPollConfig(interval: 2, timeout: 180))
    }

    // MARK: Login

    struct PendingLogin: Sendable {
        let url: URL
        let uuid: String
        let verifier: String
    }

    /// Builds the approval URL and the PKCE pair the poll will be answered with.
    func beginLogin() -> PendingLogin {
        var bytes = Data(count: 32)
        _ = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        let verifier = bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let uuid = UUID().uuidString.lowercased()

        var comps = URLComponents(string: Self.loginURL)!
        comps.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
        ]
        return PendingLogin(url: comps.url!, uuid: uuid, verifier: verifier)
    }

    /// Polls until the user approves, then stores the token.
    func completeLogin(_ pending: PendingLogin) async throws {
        guard case .browserPoll(let cfg) = auth else { throw ProviderError.notConnected }
        let deadline = Date().addingTimeInterval(cfg.timeout)

        while Date() < deadline {
            var comps = URLComponents(string: Self.pollURL)!
            comps.queryItems = [
                URLQueryItem(name: "uuid", value: pending.uuid),
                URLQueryItem(name: "verifier", value: pending.verifier),
            ]
            var req = URLRequest(url: comps.url!)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")

            if let obj = try? await JSONFetch.object(req),
               let token = obj["accessToken"] as? String, !token.isEmpty {
                CredentialStore.save(
                    Credential(apiKey: token,
                               accountLabel: obj["email"] as? String),
                    for: id)
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(cfg.interval * 1_000_000_000))
        }
        throw ProviderError.badResponse("Timed out waiting for Cursor approval.")
    }

    // MARK: Usage

    func fetchUsage(allowRefresh: Bool) async throws -> ProviderUsage {
        guard let token = CredentialStore.load(id)?.apiKey, !token.isEmpty else {
            throw ProviderError.notConnected
        }

        var req = URLRequest(url: URL(string: Self.usageURL)!)
        // Cursor's web API authenticates by session cookie; the CLI token is
        // accepted in the same slot. Bearer is sent too in case the endpoint
        // prefers it.
        req.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let obj = try await JSONFetch.object(req)

        var buckets: [Bucket] = []
        if let pct = Self.percent(obj, keys: ["planUsagePercent", "usagePercent"]) {
            buckets.append(Bucket(id: "plan", label: "Plan usage",
                                  subtitle: "billing cycle", percent: pct,
                                  resetsAt: Self.cycleEnd(obj)))
        }
        if let pct = Self.percent(obj, keys: ["thirdPartyUsagePercent"]) {
            buckets.append(Bucket(id: "third_party", label: "Third party",
                                  subtitle: nil, percent: pct,
                                  resetsAt: Self.cycleEnd(obj)))
        }

        let usage = ProviderUsage(provider: id, buckets: buckets, credits: nil,
                                  accountLabel: CredentialStore.load(id)?.accountLabel,
                                  fetchedAt: Date())
        UsageCache.save(usage)
        return usage
    }

    private static func percent(_ obj: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let n = obj[key] as? NSNumber { return n.doubleValue }
        }
        return nil
    }

    private static func cycleEnd(_ obj: [String: Any]) -> Date? {
        for key in ["billingCycleEnd", "nextResetTimestampUtc", "periodEnd"] {
            if let date = JSONFetch.date(obj[key]) { return date }
            if let ms = (obj[key] as? NSNumber)?.doubleValue, ms > 0 {
                return Date(timeIntervalSince1970: ms > 1e11 ? ms / 1000 : ms)
            }
        }
        return nil
    }
}
