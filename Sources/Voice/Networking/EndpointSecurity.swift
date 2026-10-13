import Foundation

/// Prevent credentials from being sent to a remote clear-text endpoint.
/// Local HTTP services remain supported for development and self-hosted use.
enum EndpointSecurity {
    static func allowsCredentialTransmission(to url: URL, apiKey: String) -> Bool {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "https" || scheme == "wss" {
            return true
        }
        guard scheme == "http" || scheme == "ws" else { return false }
        return isLoopbackHost(url.host)
    }

    /// True when the payload itself — audio or transcript — would cross the network
    /// in clear text. Unlike `allowsCredentialTransmission`, this stays true even when
    /// no API key is configured, so the UI can warn about exposing dictation content.
    static func isCleartextRemote(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "ws" else { return false }
        return !isLoopbackHost(url.host)
    }

    static func isCleartextRemote(endpoint: String) -> Bool {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return false }
        return isCleartextRemote(url)
    }

    /// `Bearer <key>` for `Authorization`, or nil when there is no usable key.
    ///
    /// Keys are pasted, and a paste from a file or a password manager routinely carries a
    /// trailing newline. Interpolating that straight into a header produced a request the
    /// URL loader rejects or truncates, and the user saw an unexplained failure — now with
    /// the response body redacted, so there was nothing left to diagnose it with. Callers
    /// used to trim in some paths and not others.
    static func bearerHeader(apiKey: String) -> String? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A key with an interior control character is not recoverable by trimming, and
        // sending it would smuggle whatever follows into the header block.
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return "Bearer \(trimmed)"
    }

    private static func isLoopbackHost(_ rawHost: String?) -> Bool {
        let host = (rawHost ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        guard !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") {
            return true
        }
        if host == "::1" || host == "0:0:0:0:0:0:0:1" {
            return true
        }
        return isIPv4Loopback(host)
    }

    /// Dotted-quad addresses inside 127.0.0.0/8. Any other notation (decimal, octal,
    /// shorthand such as `127.1`) fails closed rather than being treated as local.
    private static func isIPv4Loopback(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 127
    }
}
