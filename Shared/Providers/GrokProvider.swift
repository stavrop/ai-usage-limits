import Foundation

/// Grok (xAI).
///
/// Same loopback-OAuth shape as Claude. Endpoints come from xAI's own OIDC
/// discovery document (`https://auth.x.ai/.well-known/openid-configuration`), so
/// the authorize/token URLs are authoritative; the client id is the public
/// grok-cli one and the billing endpoint is undocumented.
struct GrokProvider: UsageProvider {
    let id: ProviderID = .xai

    static let usageURL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"

    var auth: AuthKind {
        .oauth(OAuthConfig(
            clientID: "b1a00492-073a-47ea-816f-4c329264a828",   // public grok-cli client
            authorizeURL: "https://auth.x.ai/oauth2/authorize",
            tokenURL: "https://auth.x.ai/oauth2/token",
            // Mirrors the grok-cli scope set. xAI advertises far more
            // (api-keys:write, conversations:write, workspaces:write …) — none of
            // which a usage monitor should ever ask for.
            scopes: "openid profile email offline_access grok-cli:access api:access",
            fixedPort: nil,          // loopback is port-agnostic here (RFC 8252)
            callbackPath: "/callback",
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
        req.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let obj = try await JSONFetch.object(req)
        let cfg = obj["config"] as? [String: Any]

        // Preferred signal is an explicit percentage; otherwise derive it from
        // on-demand used vs cap.
        var percent = (cfg?["creditUsagePercent"] as? NSNumber)?.doubleValue
        if percent == nil,
           let used = Self.amount(obj["onDemandUsed"]),
           let cap = Self.amount(obj["onDemandCap"]), cap > 0 {
            percent = used / cap * 100
        }

        let resetsAt = JSONFetch.date(Self.period(cfg)?["end"])
            ?? JSONFetch.date(cfg?["billingPeriodEnd"])

        var buckets: [Bucket] = []
        if let percent {
            buckets.append(Bucket(id: "credits", label: "Credits",
                                  subtitle: "billing period",
                                  percent: percent, resetsAt: resetsAt))
        }

        var credits: CreditInfo?
        if let used = Self.amount(obj["onDemandUsed"]) {
            let cap = Self.amount(obj["onDemandCap"])
            credits = CreditInfo(used: used, limit: cap,
                                 remaining: cap.map { $0 - used },
                                 currency: "USD", note: nil)
        }

        let usage = ProviderUsage(provider: id, buckets: buckets, credits: credits,
                                  accountLabel: CredentialStore.load(id)?.accountLabel,
                                  fetchedAt: Date())
        UsageCache.save(usage)
        return usage
    }

    private static func period(_ cfg: [String: Any]?) -> [String: Any]? {
        cfg?["currentPeriod"] as? [String: Any]
    }

    /// Amounts arrive wrapped as `{ "val": <number> }`.
    private static func amount(_ raw: Any?) -> Double? {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let d = raw as? [String: Any] { return (d["val"] as? NSNumber)?.doubleValue }
        return nil
    }
}
