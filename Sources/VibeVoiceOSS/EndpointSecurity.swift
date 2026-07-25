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

    private static func isLoopbackHost(_ rawHost: String?) -> Bool {
        let host = (rawHost ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
