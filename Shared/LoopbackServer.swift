import Foundation
import Network

/// A minimal loopback HTTP listener that catches the OAuth redirect on-device.
///
/// Why this exists: both OAuth providers redirect to `http://localhost:<port>/…`
/// (Claude verified 2026-08-25; OpenAI pins port 1455), but
/// `ASWebAuthenticationSession` can only auto-detect *custom-scheme* or
/// *universal-link* callbacks — and we can't register either against a public
/// client id we don't own. So we do what their CLIs do: actually listen on a
/// local port and serve the redirect ourselves.
///
/// Bound to 127.0.0.1 only, so it is unreachable from the network and does not
/// trip iOS's local-network privacy prompt. It lives exactly as long as one
/// sign-in attempt.
final class LoopbackServer: @unchecked Sendable {

    struct Callback {
        let code: String
        let state: String
    }

    enum ServerError: LocalizedError {
        case cannotBind
        case cancelled
        case authorizeFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotBind:
                return "Couldn't open a local port to complete sign-in."
            case .cancelled:
                return "Sign-in was cancelled."
            case .authorizeFailed(let m):
                return "The provider declined the sign-in: \(m)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.local.claudeusage.loopback")
    private let lock = NSLock()

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var waiter: CheckedContinuation<Callback, Error>?
    private var settled = false
    private var pending: Result<Callback, Error>?
    /// Guards the one-shot resume of `start()`'s continuation. NWListener can
    /// report `.ready` and later `.failed`, and its handler runs on `queue`, so
    /// this must be lock-protected rather than a captured local var.
    private var startResumed = false

    private(set) var port: UInt16 = 0

    // MARK: - Lifecycle

    /// Binds a loopback port and returns it. Throws if the listener never
    /// reaches `.ready`.
    ///
    /// `fixedPort` is required by providers that registered an exact redirect —
    /// OpenAI pins 1455 for the Codex client, so an ephemeral port is rejected at
    /// the authorize step. Claude accepts any high port, so it passes nil.
    /// A fixed port can legitimately fail to bind if something else holds it
    /// (e.g. a desktop CLI mid-login on the same machine), which surfaces as
    /// `.cannotBind`.
    func start(fixedPort: UInt16? = nil) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Constrain to loopback; let the system pick the port unless pinned.
        let requested: NWEndpoint.Port = fixedPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: requested)

        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            throw ServerError.cannotBind
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        // NWListener reports bind failures through its state handler, not the
        // initializer, so wait for .ready before handing back a port.
        let boundPort: UInt16 = try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                let outcome: Result<UInt16, Error>
                switch state {
                case .ready:
                    outcome = .success(listener.port?.rawValue ?? 0)
                case .failed, .cancelled:
                    outcome = .failure(ServerError.cannotBind)
                default:
                    return
                }
                self.lock.lock()
                let alreadyResumed = self.startResumed
                self.startResumed = true
                self.lock.unlock()
                guard !alreadyResumed else { return }
                cont.resume(with: outcome)
            }
            listener.start(queue: queue)
        }

        guard boundPort != 0 else { throw ServerError.cannotBind }
        port = boundPort
        return boundPort
    }

    func stop() {
        lock.lock()
        let conns = connections
        connections = []
        lock.unlock()

        conns.forEach { $0.cancel() }
        listener?.cancel()
        listener = nil
    }

    // MARK: - Waiting

    /// Suspends until the browser hits `/callback`, or until `fail(_:)` is called.
    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if let pending {
                lock.unlock()
                cont.resume(with: pending)
                return
            }
            waiter = cont
            lock.unlock()
        }
    }

    /// Unblocks `waitForCallback` with an error — used when the user dismisses
    /// the web sheet, so the flow doesn't hang forever.
    func fail(_ error: Error) {
        settle(.failure(error))
    }

    private func settle(_ result: Result<Callback, Error>) {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true
        let cont = waiter
        waiter = nil
        if cont == nil { pending = result }
        lock.unlock()
        cont?.resume(with: result)
    }

    // MARK: - HTTP

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()

        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.handle(request: request, on: connection)
        }
    }

    private func handle(request: String, on connection: NWConnection) {
        // First line looks like: GET /callback?code=…&state=… HTTP/1.1
        guard let requestLine = request.split(separator: "\r\n").first else {
            respond(body: Self.errorPage, on: connection)
            return
        }
        let fields = requestLine.split(separator: " ")
        guard fields.count >= 2 else {
            respond(body: Self.errorPage, on: connection)
            return
        }

        // Any path is accepted: providers differ (Claude redirects to /callback,
        // OpenAI to /auth/callback) and this listener is bound to one ephemeral
        // loopback port for the lifetime of a single sign-in, so there is nothing
        // else it could be receiving.
        let target = String(fields[1])
        guard let comps = URLComponents(string: "http://localhost" + target) else {
            respond(body: Self.errorPage, on: connection)
            return
        }

        func value(_ name: String) -> String? {
            comps.queryItems?.first { $0.name == name }?.value
        }

        if let error = value("error") {
            let detail = value("error_description") ?? error
            respond(body: Self.errorPage, on: connection)
            settle(.failure(ServerError.authorizeFailed(detail)))
            return
        }

        guard let code = value("code"), let state = value("state") else {
            respond(body: Self.errorPage, on: connection)
            return
        }

        respond(body: Self.successPage, on: connection)
        settle(.success(Callback(code: code, state: state)))
    }

    private func respond(body: String, on connection: NWConnection) {
        let payload = Data(body.utf8)
        let head = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(payload.count)\r
        Connection: close\r
        \r

        """
        var out = Data(head.utf8)
        out.append(payload)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // The sheet is dismissed programmatically the moment the code arrives, so
    // these pages are only ever glimpsed.
    private static let successPage = """
    <!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
    <body style="font:-apple-system-body;padding:3rem;text-align:center">
    <h2>Signed in</h2><p>You can return to AI Usage Limits.</p></body>
    """

    private static let errorPage = """
    <!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
    <body style="font:-apple-system-body;padding:3rem;text-align:center">
    <h2>Sign-in failed</h2><p>Return to the app and try again.</p></body>
    """
}
