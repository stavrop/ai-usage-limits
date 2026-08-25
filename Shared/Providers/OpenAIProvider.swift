import Foundation

/// ChatGPT / Codex subscription limits.
///
/// Same loopback-OAuth shape as Claude, with one difference that matters: OpenAI
/// registered an exact redirect for the Codex client, so the listener must bind
/// port **1455** — an ephemeral port is rejected.
///
/// The usage endpoint is the one the Codex CLI polls; it is undocumented and may
/// change without notice.
struct OpenAIProvider: UsageProvider {
    let id: ProviderID = .openai

    static let usageURL = "https://chatgpt.com/backend-api/wham/usage"

    var auth: AuthKind {
        .oauth(OAuthConfig(
            clientID: "app_EMoamEEZ73f0CkXaXp7hrann",   // public Codex client
            authorizeURL: "https://auth.openai.com/oauth/authorize",
            tokenURL: "https://auth.openai.com/oauth/token",
            // Mirrors the Codex CLI's own scopes. The api.connectors.* pair is
            // required to reach the usage endpoint — omitting them was likely to
            // fail on first contact. `invoke` is a candidate to drop once the
            // read-only path is confirmed working without it.
            scopes: "openid profile email offline_access "
                + "api.connectors.read api.connectors.invoke",
            fixedPort: 1455,                            // exact registered redirect
            callbackPath: "/auth/callback",
            extraAuthorizeItems: [:],
            exchangeHeaders: [:],
            userAgent: Config.userAgent
        ))
    }

    private var config: OAuthConfig {
        guard case .oauth(let c) = auth else { fatalError("unreachable") }
        return c
    }

    func fetchUsage(allowRefresh: Bool) async throws -> ProviderUsage {
        let token = try await OAuthClient.shared.validAccessToken(
            provider: id, config: config, allowRefresh: allowRefresh)

        var req = URLRequest(url: URL(string: Self.usageURL)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // The backend needs the account id alongside the bearer token. It is
        // captured from the id_token at sign-in and stored with the credential.
        if let accountID = CredentialStore.load(id)?.extras?["account_id"] {
            req.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let obj = try await JSONFetch.object(req)

        var buckets: [Bucket] = []
        if let limits = obj["rate_limit"] as? [String: Any] {
            if let b = Self.parseWindow(limits["primary_window"], id: "primary") {
                buckets.append(b)
            }
            if let b = Self.parseWindow(limits["secondary_window"], id: "secondary") {
                buckets.append(b)
            }
        }
        if let review = obj["code_review_rate_limit"] as? [String: Any],
           let b = Self.parseWindow(review["primary_window"], id: "code_review",
                                    labelOverride: "Code review") {
            buckets.append(b)
        }

        var credits: CreditInfo?
        if let c = obj["credits"] as? [String: Any],
           (c["has_credits"] as? Bool) == true {
            credits = CreditInfo(
                used: (c["used"] as? NSNumber)?.doubleValue,
                limit: (c["limit"] as? NSNumber)?.doubleValue,
                remaining: (c["balance"] as? NSNumber)?.doubleValue,
                currency: (c["currency"] as? String) ?? "USD",
                note: nil)
        }

        let usage = ProviderUsage(provider: id, buckets: buckets, credits: credits,
                                  accountLabel: CredentialStore.load(id)?.accountLabel,
                                  fetchedAt: Date())
        UsageCache.save(usage)
        return usage
    }

    /// Window labels are derived from `limit_window_seconds`, the way the macOS
    /// app does it — the payload names the duration, not the window.
    private static func parseWindow(_ raw: Any?, id: String,
                                    labelOverride: String? = nil) -> Bucket? {
        guard let d = raw as? [String: Any] else { return nil }
        guard let pct = (d["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let seconds = (d["limit_window_seconds"] as? NSNumber)?.doubleValue ?? 0
        let label = labelOverride ?? Self.windowLabel(seconds)
        var resetsAt = JSONFetch.date(d["reset_at"])
        if resetsAt == nil, let after = (d["resets_in_seconds"] as? NSNumber)?.doubleValue {
            resetsAt = Date().addingTimeInterval(after)
        }
        return Bucket(id: id, label: label,
                      subtitle: seconds > 0 ? Self.windowSubtitle(seconds) : nil,
                      percent: pct, resetsAt: resetsAt)
    }

    private static func windowLabel(_ seconds: Double) -> String {
        switch seconds {
        case 0: return "Usage"
        case ..<7200: return "Hourly"
        case ..<86_400: return "\(Int(seconds / 3600))-hour"
        case ..<604_800: return "Daily"
        case ..<2_592_000: return "Weekly"
        default: return "Monthly"
        }
    }

    private static func windowSubtitle(_ seconds: Double) -> String {
        if seconds < 86_400 { return "\(Int(seconds / 3600))-hour window" }
        return "\(Int(seconds / 86_400))-day window"
    }
}
