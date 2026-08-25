import Foundation
import CryptoKit

/// One in-flight authorization attempt.
struct AuthorizationRequest: Sendable {
    let url: URL
    let verifier: String
    let state: String
    let redirectURI: String
}

/// PKCE authorization-code login + silent refresh, shared by every OAuth provider.
///
/// Both supported OAuth providers use the same shape — a public client, PKCE, and
/// a loopback redirect caught by an on-device listener:
///
///   • Claude  — any high port; state MUST be 32 bytes or authorize returns
///               "Invalid request format".
///   • ChatGPT — pinned to port 1455 (`OAuthConfig.fixedPort`), because OpenAI
///               registered that exact redirect for the Codex client.
///
/// Verified live for Claude on 2026-08-25: authorize → exchange 200 → refresh 200.
actor OAuthClient {
    static let shared = OAuthClient()

    // MARK: PKCE helpers

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func randomString(_ bytes: Int = 32) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!)
        }
        return base64URL(data)
    }

    // MARK: Login

    /// Builds the authorization URL for a bound loopback port.
    ///
    /// `state` and the verifier are both 32 bytes (43 base64url chars), matching
    /// the reference CLIs exactly. A 16-byte state is rejected by Claude with
    /// "Invalid request format" — that width mismatch, not the redirect or the
    /// scopes, is what defeated the first attempt at this flow.
    func beginAuthorization(config: OAuthConfig, port: UInt16) -> AuthorizationRequest {
        let verifier = randomString(32)
        let state = randomString(32)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let redirectURI = "http://localhost:\(port)\(config.callbackPath)"

        var comps = URLComponents(string: config.authorizeURL)!
        var items = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: config.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        for (name, value) in config.extraAuthorizeItems.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: name, value: value))
        }
        comps.queryItems = items

        return AuthorizationRequest(url: comps.url!, verifier: verifier,
                                    state: state, redirectURI: redirectURI)
    }

    /// Exchanges an authorization code for a token pair and stores it.
    @discardableResult
    func exchange(code raw: String,
                  request: AuthorizationRequest,
                  config: OAuthConfig,
                  provider: ProviderID) async throws -> Credential {
        // Some providers render the code as `code#state`.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts.first ?? trimmed
        let state = parts.count > 1 ? parts[1] : request.state

        let credential = try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": request.redirectURI,
            "client_id": config.clientID,
            "code_verifier": request.verifier,
            "state": state,
        ], config: config, extraHeaders: config.exchangeHeaders, existing: nil)

        CredentialStore.save(credential, for: provider)
        return credential
    }

    // MARK: Refresh

    /// Returns a usable access token, refreshing first if it has expired.
    func validAccessToken(provider: ProviderID,
                          config: OAuthConfig,
                          allowRefresh: Bool) async throws -> String {
        guard let credential = CredentialStore.load(provider),
              let token = credential.accessToken else {
            throw ProviderError.notConnected
        }
        guard credential.isExpired else { return token }
        guard allowRefresh, let refreshToken = credential.refreshToken else {
            throw ProviderError.sessionExpired
        }
        let renewed = try await refresh(provider: provider, config: config,
                                        refreshToken: refreshToken, existing: credential)
        guard let fresh = renewed.accessToken else { throw ProviderError.sessionExpired }
        return fresh
    }

    /// Renews the pair and persists the rotated refresh token.
    @discardableResult
    func refresh(provider: ProviderID,
                 config: OAuthConfig,
                 refreshToken: String,
                 existing: Credential?) async throws -> Credential {
        var body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ]
        // Replay the GRANTED scope. Claude's authorize request asks for
        // org:create_api_key (required, or authorize 400s) but the server never
        // grants it — echoing the requested list back here is a 400
        // invalid_scope. Note also: no exchange-only headers on refresh.
        if let scope = existing?.scope, !scope.isEmpty {
            body["scope"] = scope
        }
        do {
            let credential = try await postToken(body, config: config,
                                                 extraHeaders: [:], existing: existing)
            CredentialStore.save(credential, for: provider)
            return credential
        } catch ProviderError.unauthorized {
            // The chain is dead (expired, revoked, or rotated out from under us).
            // Clear it so the UI offers a clean reconnect.
            CredentialStore.clear(provider)
            throw ProviderError.sessionExpired
        }
    }

    // MARK: Networking

    private func postToken(_ body: [String: Any],
                           config: OAuthConfig,
                           extraHeaders: [String: String],
                           existing: Credential?) async throws -> Credential {
        var req = URLRequest(url: URL(string: config.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Some token hosts sit behind Cloudflare and answer unrecognised clients
        // with 403 "error code: 1010" before the endpoint sees the request.
        if let ua = config.userAgent {
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }

        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1

        guard (200...299).contains(status), let obj,
              let access = obj["access_token"] as? String else {
            if status == 401 { throw ProviderError.unauthorized }
            if let err = obj?["error"] as? String,
               err == "invalid_grant" || err == "invalid_request" || err == "invalid_scope" {
                throw ProviderError.unauthorized
            }
            let detail = (obj?["error_description"] as? String)
                ?? (obj?["error"] as? String)
                ?? String(data: data, encoding: .utf8)?.prefix(200).description
                ?? "no body"
            throw ProviderError.badResponse("Token request failed (HTTP \(status)): \(detail)")
        }

        var expiresAt: Date?
        if let secs = obj["expires_in"] as? Double {
            expiresAt = Date().addingTimeInterval(secs)
        }
        // An id_token, when present, carries the account identity we need to
        // call the provider's API (OpenAI's backend requires the account id as a
        // header) plus a human label for Settings.
        var extras = existing?.extras ?? [:]
        var accountLabel = existing?.accountLabel
        if let idToken = obj["id_token"] as? String,
           let claims = Self.jwtClaims(idToken) {
            if let email = claims["email"] as? String { accountLabel = email }
            if let accountID = Self.chatGPTAccountID(in: claims) {
                extras["account_id"] = accountID
            }
        }

        return Credential(
            accessToken: access,
            // The refresh token rotates on every use for both providers;
            // persisting the new one is mandatory or the next refresh fails.
            refreshToken: (obj["refresh_token"] as? String) ?? body["refresh_token"] as? String,
            expiresAt: expiresAt,
            scope: (obj["scope"] as? String) ?? existing?.scope,
            apiKey: nil,
            extras: extras.isEmpty ? nil : extras,
            accountLabel: accountLabel
        )
    }

    // MARK: JWT

    /// Decodes a JWT payload WITHOUT verifying it. We never make a trust decision
    /// on these claims — they only supply a display label and the account id
    /// header. The provider's API is the authority.
    private static func jwtClaims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    /// OpenAI nests the ChatGPT account id under a namespaced auth claim.
    private static func chatGPTAccountID(in claims: [String: Any]) -> String? {
        for (key, value) in claims where key.hasSuffix("/auth") {
            if let auth = value as? [String: Any],
               let id = auth["chatgpt_account_id"] as? String {
                return id
            }
        }
        return claims["chatgpt_account_id"] as? String
    }
}
