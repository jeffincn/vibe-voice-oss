import Foundation

/// Turns an HTTP error body into something safe to put in a user-facing message.
///
/// Provider errors routinely echo the offending request back, `Authorization`
/// header included, and a proxy or captive portal answering in place of the API
/// can return megabytes of HTML. Both used to reach the UI verbatim, so an
/// error toast or a pasted bug report could carry a live API key.
enum HTTPErrorBody {
    static let characterLimit = 512

    static func summarize(_ data: Data, fallback: String = "未知错误") -> String {
        guard !data.isEmpty else { return fallback }
        // Decode only what could ever be displayed; the rest is dropped unread.
        let head = data.prefix(characterLimit * 8)
        return summarize(String(decoding: head, as: UTF8.self), fallback: fallback)
    }

    static func summarize(_ text: String, fallback: String = "未知错误") -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        let redacted = redactingSecrets(in: collapsed)
        guard !redacted.isEmpty else { return fallback }
        guard redacted.count > characterLimit else { return redacted }
        return String(redacted.prefix(characterLimit)) + "…"
    }

    /// Masks credentials in whatever shape the provider echoed them back.
    static func redactingSecrets(in text: String) -> String {
        var result = text
        for rule in redactionRules {
            result = rule.expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.template
            )
        }
        return result
    }

    private struct RedactionRule {
        let expression: NSRegularExpression
        let template: String
    }

    private static let redactionRules: [RedactionRule] = {
        let patterns: [(String, String)] = [
            // Authorization: Bearer <token>
            (#"(?i)\bbearer\s+[A-Za-z0-9._\-]+"#, "Bearer ***"),
            // Bare OpenAI-style keys pasted into a body or query string.
            (#"\bsk-[A-Za-z0-9._\-]{8,}"#, "sk-***"),
            // "api_key": "…", api-key=…, token: …, in JSON, form and query bodies.
            (
                #"(?i)("?(?:api[_-]?key|access[_-]?token|auth[_-]?token|token|secret)"?\s*[:=]\s*"?)[^"\s,}&]{6,}"#,
                "$1***"
            ),
        ]
        return patterns.compactMap { pattern, template in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
            return RedactionRule(expression: expression, template: template)
        }
    }()
}
