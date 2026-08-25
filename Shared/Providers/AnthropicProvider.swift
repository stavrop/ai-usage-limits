import Foundation

/// Claude (Anthropic subscription).
///
/// Endpoints and request shapes ground-truthed from the Claude Code 2.1.231
/// binary and verified live on 2026-08-25.
struct AnthropicProvider: UsageProvider {
    let id: ProviderID = .anthropic

    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    static let oauthBeta = "oauth-2025-04-20"

    var auth: AuthKind {
        .oauth(OAuthConfig(
            clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            // 302s to claude.ai/oauth/authorize; that's expected.
            authorizeURL: "https://claude.com/cai/oauth/authorize",
            tokenURL: "https://platform.claude.com/v1/oauth/token",
            // MINIMAL read-only request, verified live 2026-08-25.
            //
            // org:create_api_key MUST be requested or authorize returns
            // "Invalid request format" — but the server does NOT grant it. The
            // issued token comes back scoped to `user:profile` alone: it can read
            // usage and cannot send prompts or spend the allowance.
            //
            // Do NOT widen this to the full Claude Code CLI list
            // (user:inference, user:sessions:claude_code, user:mcp_servers,
            // user:file_upload). Those ARE granted, and a usage monitor holding a
            // token that can spend the user's allowance is indefensible.
            scopes: "org:create_api_key user:profile",
            fixedPort: nil,              // any high port is accepted
            callbackPath: "/callback",
            extraAuthorizeItems: ["code": "true"],
            exchangeHeaders: ["anthropic-beta": Self.oauthBeta],
            // platform.claude.com is Cloudflare-fronted and 403s unrecognised
            // clients with "error code: 1010".
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
        do {
            return try await fetchOnce(token: token)
        } catch ProviderError.unauthorized {
            // Live by our clock but rejected by the server: one forced refresh
            // covers clock skew and server-side revocation.
            guard allowRefresh,
                  let credential = CredentialStore.load(id),
                  let refreshToken = credential.refreshToken else {
                throw ProviderError.sessionExpired
            }
            let renewed = try await OAuthClient.shared.refresh(
                provider: id, config: config,
                refreshToken: refreshToken, existing: credential)
            guard let fresh = renewed.accessToken else { throw ProviderError.sessionExpired }
            do {
                return try await fetchOnce(token: fresh)
            } catch ProviderError.unauthorized {
                throw ProviderError.sessionExpired
            }
        }
    }

    private func fetchOnce(token: String) async throws -> ProviderUsage {
        var req = URLRequest(url: URL(string: Self.usageURL)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.oauthBeta, forHTTPHeaderField: "anthropic-beta")

        let obj = try await JSONFetch.object(req)

        var buckets: [Bucket] = []
        if let b = Self.parseBucket(obj["five_hour"], id: "five_hour",
                                   label: "Session", subtitle: "5-hour window") {
            buckets.append(b)
        }
        if let b = Self.parseBucket(obj["seven_day"], id: "seven_day",
                                   label: "Weekly", subtitle: "7-day, all models") {
            buckets.append(b)
        }
        // Scoped weekly buckets are usually null now; label follows whichever
        // actually parsed rather than assuming Opus-or-Sonnet.
        for (key, name) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")] {
            if let b = Self.parseBucket(obj[key], id: key,
                                        label: "Weekly · \(name)",
                                        subtitle: "7-day, one model") {
                buckets.append(b)
                break
            }
        }

        // `extra_usage` is the pay-as-you-go credit pool the macOS app shows.
        var credits: CreditInfo?
        if let extra = obj["extra_usage"] as? [String: Any],
           (extra["is_enabled"] as? Bool) == true {
            let used = (extra["used_credits"] as? NSNumber)?.doubleValue
            let limit = (extra["monthly_limit"] as? NSNumber)?.doubleValue
            let remaining = (limit != nil && used != nil) ? limit! - used! : nil
            credits = CreditInfo(used: used, limit: limit, remaining: remaining,
                                 currency: (extra["currency"] as? String) ?? "USD",
                                 note: nil)
        }

        let usage = ProviderUsage(provider: id, buckets: buckets, credits: credits,
                                  accountLabel: CredentialStore.load(id)?.accountLabel,
                                  fetchedAt: Date())
        UsageCache.save(usage)
        return usage
    }

    /// `utilization` arrives as a float (e.g. 24.0) — keep it a Double so we
    /// don't report 24% for 24.9%.
    private static func parseBucket(_ raw: Any?, id: String,
                                    label: String, subtitle: String?) -> Bucket? {
        guard let d = raw as? [String: Any] else { return nil }
        let pct = (d["percent"] as? NSNumber)?.doubleValue
            ?? (d["utilization"] as? NSNumber)?.doubleValue
        guard let pct else { return nil }
        return Bucket(id: id, label: label, subtitle: subtitle,
                      percent: pct, resetsAt: JSONFetch.date(d["resets_at"]))
    }
}
