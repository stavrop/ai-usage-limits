import AuthenticationServices
import Foundation
import UIKit

/// Connects a provider: runs the browser half of OAuth, or verifies a pasted key.
///
/// `ASWebAuthenticationSession` runs a real Safari instance out of process, which
/// is what lets Claude's Arkose (FunCaptcha) check pass — it fingerprints the
/// runtime and refuses an embedded WKWebView.
@MainActor
final class ProviderConnector: NSObject, ASWebAuthenticationPresentationContextProviding {

    enum ConnectError: LocalizedError {
        case cannotPresent
        case stateMismatch
        case portUnavailable(UInt16)
        case notSupported

        var errorDescription: String? {
            switch self {
            case .cannotPresent:
                return "Couldn't open the sign-in page."
            case .stateMismatch:
                return "The sign-in response didn't match the request. Please try again."
            case .portUnavailable(let port):
                return "Port \(port) is busy, and this provider requires it for sign-in. "
                    + "Close anything else signing in to it and try again."
            case .notSupported:
                return "This provider can't be connected this way."
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    /// Runs OAuth end to end: bind the loopback port, open Safari, capture the
    /// redirect, exchange the code. Returns once credentials are stored.
    func connectOAuth(provider: any UsageProvider) async throws {
        guard case .oauth(let config) = provider.auth else { throw ConnectError.notSupported }

        let server = LoopbackServer()
        let port: UInt16
        do {
            port = try await server.start(fixedPort: config.fixedPort)
        } catch {
            // A pinned port is the only one that can be legitimately unavailable.
            if let fixed = config.fixedPort { throw ConnectError.portUnavailable(fixed) }
            throw error
        }
        defer { server.stop() }

        let request = await OAuthClient.shared.beginAuthorization(config: config, port: port)

        // The callback scheme never fires — our redirect is http://localhost,
        // which ASWebAuthenticationSession can't match. The loopback listener is
        // what completes the flow; this handler only tells us the user dismissed
        // the sheet, so the await below doesn't hang forever.
        let session = ASWebAuthenticationSession(
            url: request.url,
            callbackURLScheme: "aiusagemonitor"
        ) { _, error in
            if let error { server.fail(error) }
        }
        session.presentationContextProvider = self
        // Reuse Safari's cookies: an already-signed-in user just taps Approve.
        session.prefersEphemeralWebBrowserSession = false

        self.session = session
        guard session.start() else { throw ConnectError.cannotPresent }
        defer { session.cancel(); self.session = nil }

        let callback = try await server.waitForCallback()
        guard callback.state == request.state else { throw ConnectError.stateMismatch }

        try await OAuthClient.shared.exchange(code: callback.code, request: request,
                                              config: config, provider: provider.id)
    }

    /// Opens the provider's approval page and polls until it issues a token.
    ///
    /// Unlike OAuth there's no redirect to catch, so the Safari sheet stays open
    /// until the poll succeeds; we dismiss it ourselves.
    func connectBrowserPoll(provider: any UsageProvider) async throws {
        guard let cursor = provider as? CursorProvider else { throw ConnectError.notSupported }
        let pending = cursor.beginLogin()

        let session = ASWebAuthenticationSession(
            url: pending.url,
            callbackURLScheme: "aiusagemonitor"
        ) { _, _ in }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false

        self.session = session
        guard session.start() else { throw ConnectError.cannotPresent }
        defer { session.cancel(); self.session = nil }

        try await cursor.completeLogin(pending)
    }

    /// Stores and verifies a pasted API key, keeping it only if it works.
    func connectAPIKey(provider: any UsageProvider, key: String) async throws {
        if let openRouter = provider as? OpenRouterProvider {
            _ = try await openRouter.verifyAndStore(apiKey: key)
            return
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProviderError.notConnected }
        CredentialStore.save(Credential(apiKey: trimmed), for: provider.id)
        do {
            _ = try await provider.fetchUsage(allowRefresh: false)
        } catch {
            CredentialStore.clear(provider.id)
            throw error
        }
    }

    /// True when dismissing the sheet caused the failure — not worth an alert.
    static func isUserCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == ASWebAuthenticationSessionErrorDomain
            && ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }

    // MARK: ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
