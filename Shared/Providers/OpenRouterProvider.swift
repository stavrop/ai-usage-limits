import Foundation

/// OpenRouter.
///
/// The only provider here with a *supported, documented* usage API, and the
/// simplest to connect: the user pastes a key from their dashboard, no browser
/// round trip. https://openrouter.ai/docs/api-reference/limits
struct OpenRouterProvider: UsageProvider {
    let id: ProviderID = .openrouter

    static let keyURL = "https://openrouter.ai/api/v1/key"

    var auth: AuthKind {
        .apiKey(APIKeyConfig(
            instructions: "Paste an OpenRouter API key. It's read-only here — used "
                + "solely to read your credit limit and remaining balance.",
            dashboardURL: "https://openrouter.ai/settings/keys",
            placeholder: "sk-or-v1-…"
        ))
    }

    func fetchUsage(allowRefresh: Bool) async throws -> ProviderUsage {
        guard let key = CredentialStore.load(id)?.apiKey, !key.isEmpty else {
            throw ProviderError.notConnected
        }

        var req = URLRequest(url: URL(string: Self.keyURL)!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let root = try await JSONFetch.object(req)
        // The documented payload nests everything under "data".
        let d = (root["data"] as? [String: Any]) ?? root

        let usage = (d["usage"] as? NSNumber)?.doubleValue
        let limit = (d["limit"] as? NSNumber)?.doubleValue
        let remaining = (d["limit_remaining"] as? NSNumber)?.doubleValue

        // A key with no cap has limit == null. Showing a 0% ring for "unlimited"
        // would be a lie, so emit a bucket only when there is a real ceiling.
        var buckets: [Bucket] = []
        if let limit, limit > 0, let usage {
            buckets.append(Bucket(
                id: "credits",
                label: "Credits",
                subtitle: (d["limit_reset"] as? String).map { "resets \($0)" } ?? "no reset",
                percent: min(usage / limit * 100, 100),
                resetsAt: nil))
        }

        let credits = CreditInfo(
            used: usage,
            limit: limit,
            remaining: remaining ?? limit.map { $0 - (usage ?? 0) },
            currency: "USD",
            note: limit == nil ? "Unlimited key — usage only" : nil)

        let result = ProviderUsage(
            provider: id,
            buckets: buckets,
            credits: credits,
            accountLabel: d["label"] as? String,
            fetchedAt: Date())
        UsageCache.save(result)
        return result
    }

    /// Validates a pasted key by actually calling the API, so a typo is caught at
    /// entry rather than showing an empty card later.
    func verifyAndStore(apiKey: String) async throws -> ProviderUsage {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProviderError.notConnected }
        CredentialStore.save(Credential(apiKey: trimmed), for: id)
        do {
            return try await fetchUsage(allowRefresh: false)
        } catch {
            CredentialStore.clear(id)   // don't keep a key that doesn't work
            throw error
        }
    }
}
