import Foundation

/// Small shared HTTP/JSON helper so each provider doesn't restate the same
/// status-code and date-parsing handling.
enum JSONFetch {

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    /// Parses an ISO-8601 string, with or without fractional seconds.
    static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }

    /// Performs the request and returns a JSON object, mapping transport and
    /// status failures onto `ProviderError`.
    static func object(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: request)
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw ProviderError.badResponse("Unexpected response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw ProviderError.rateLimited(retryAfter: retry)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw ProviderError.badResponse("HTTP \(http.statusCode): \(body)")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let body = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            throw ProviderError.badResponse("Non-JSON response: \(body)")
        }
        return obj
    }
}
