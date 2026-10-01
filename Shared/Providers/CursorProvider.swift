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
/// least certain provider in the app. Login, cookie format and the usage payload
/// were verified against a live free account on 2026-10-01.
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
        // Cursor's web API authenticates by session cookie, and the cookie value
        // is `<user id>%3A%3A<token>`. The bare CLI token is rejected with 401
        // (verified live 2026-10-01), as is a Bearer header alone.
        req.setValue("WorkosCursorSessionToken=\(Self.cookieValue(token))",
                     forHTTPHeaderField: "Cookie")
        req.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")

        let obj = try await JSONFetch.object(req)
        let plan = (obj["individualUsage"] as? [String: Any])?["plan"] as? [String: Any]
        let resets = Self.cycleEnd(obj)

        var buckets: [Bucket] = []
        if let pct = Self.percent(plan, keys: ["totalPercentUsed"]) {
            buckets.append(Bucket(id: "plan", label: "Plan usage",
                                  subtitle: "billing cycle", percent: pct, resetsAt: resets))
        }
        if let pct = Self.percent(plan, keys: ["autoPercentUsed"]) {
            buckets.append(Bucket(id: "auto", label: "Auto + Composer",
                                  subtitle: nil, percent: pct, resetsAt: resets))
        }
        if let pct = Self.percent(plan, keys: ["apiPercentUsed"]) {
            buckets.append(Bucket(id: "api", label: "API models",
                                  subtitle: nil, percent: pct, resetsAt: resets))
        }

        let usage = ProviderUsage(provider: id, buckets: buckets, credits: nil,
                                  accountLabel: CredentialStore.load(id)?.accountLabel,
                                  fetchedAt: Date())
        UsageCache.save(usage)
        return usage
    }

    private static func percent(_ obj: [String: Any]?, keys: [String]) -> Double? {
        for key in keys {
            if let n = obj?[key] as? NSNumber { return n.doubleValue }
        }
        return nil
    }

    /// `<user id>%3A%3A<token>`. The user id is the JWT `sub` without its
    /// `auth0|` prefix. If the token is not a decodable JWT, fall back to bare.
    static func cookieValue(_ token: String) -> String {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return token }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = claims["sub"] as? String,
              let userID = sub.split(separator: "|").last else { return token }
        return "\(userID)%3A%3A\(token)"
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
