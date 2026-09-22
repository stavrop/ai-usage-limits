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
        // Anthropic sends ISO-8601 strings; ChatGPT sends a Unix epoch as a
        // number. Parsing only the former silently dropped every ChatGPT reset
        // time, which the macOS app shows.
        if let s = any as? String {
            return isoFractional.date(from: s) ?? iso.date(from: s)
        }
        if let n = any as? NSNumber {
            let seconds = n.doubleValue
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
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
