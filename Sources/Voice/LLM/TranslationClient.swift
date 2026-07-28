import Foundation

struct TranslationConfiguration: Sendable {
    let endpoint: String
    let model: String
    let targetLanguage: String
    let styleHint: String
    var customSystemPrompt: String = ""
    /// Professional context appended after the user's explicit custom instructions.
    var roleContextPrompt: String = ""
    let apiKey: String
    let task: LanguageModelTask
    /// Used only when `task == .optimizePrompt`.
    var promptTarget: PromptTargetKind = .codingCodex
}

enum TranslationError: LocalizedError {
    case invalidEndpoint
    case server(status: Int, message: String)
    case invalidResponse
    case emptyText
    case timedOut(seconds: Int)
    case promptCompile(String)
    case insecureEndpoint
    case japaneseModelTooOld

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: L10n.t(.errLLMInvalidEndpoint)
        case let .server(status, message): L10n.t(.errLLMServer, status, message)
        case .invalidResponse: L10n.t(.errLLMInvalidResponse)
        case .emptyText: L10n.t(.errLLMEmptyText)
        case let .timedOut(seconds): L10n.t(.errLLMTimedOut, seconds)
        case let .promptCompile(detail): L10n.t(.errPromptCompile, detail)
        case .insecureEndpoint: L10n.t(.errInsecureEndpoint)
        case .japaneseModelTooOld: L10n.t(.japaneseModelRequirement)
        }
    }
}

struct TranslationClient: Sendable {
    private static let requestTimeoutSeconds = 180
    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let reasoningContent: String?

                enum CodingKeys: String, CodingKey {
                    case content
                    case reasoningContent = "reasoning_content"
                }
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }
        let data: [Model]
    }

    /// Collapse pasted multi-line model IDs (common when copying from model lists).
    static func sanitizeModelName(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.first ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the first major/minor version-like number in a model identifier.
    /// The first match avoids mistaking a parameter count such as 35B for a version.
    static func modelVersion(_ raw: String) -> Double? {
        let pattern = #"(?<![0-9])([0-9]+)(?:\.([0-9]+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let majorRange = Range(match.range(at: 1), in: raw),
              let major = Double(raw[majorRange]) else { return nil }
        guard match.range(at: 2).location != NSNotFound,
              let minorRange = Range(match.range(at: 2), in: raw),
              let minor = Double("0." + raw[minorRange]) else {
            return major
        }
        return major + minor
    }

    static func supportsJapaneseNaturalTranslation(model raw: String) -> Bool {
        guard let version = modelVersion(raw) else { return false }
        return version >= 5.6
    }

    /// Derive OpenAI `/v1/models` from a chat-completions URL (`…/v1/chat/completions`).
    /// Mirrors ASR: strip two trailing segments (`chat` + `completions`), then append `models`.
    static func modelsProbeURL(from chatCompletionsURL: URL) -> URL {
        chatCompletionsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models")
    }

    /// Probe reachability: optional `/v1/models` list, then a real `chat/completions` ping.
    ///
    /// NVIDIA Integrate and similar hosts often allow `GET /v1/models` while rejecting
    /// `POST /v1/chat/completions` with 401/403 (missing inference permission or gated model).
    /// A list-only probe therefore gives false confidence — the chat ping is authoritative.
    func checkServer(configuration: TranslationConfiguration) async throws -> String {
        let model = Self.sanitizeModelName(configuration.model)
        guard !model.isEmpty else {
            throw TranslationError.server(status: 404, message: "未配置翻译模型名。")
        }
        if configuration.targetLanguage == "Japanese",
           !Self.supportsJapaneseNaturalTranslation(model: model) {
            throw TranslationError.japaneseModelTooOld
        }
        guard let chatURL = URL(string: configuration.endpoint) else {
            throw TranslationError.invalidEndpoint
        }
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EndpointSecurity.allowsCredentialTransmission(to: chatURL, apiKey: apiKey) else {
            throw TranslationError.insecureEndpoint
        }

        let profile = LLMProviderProfile.resolve(
            endpoint: configuration.endpoint, model: model
        )

        // Soft check: confirm model appears in the catalog when the host exposes one.
        let modelsURL = Self.modelsProbeURL(from: chatURL)
        if let ids = try? await fetchModelIDs(from: modelsURL, apiKey: apiKey, profile: profile) {
            let matched = ids.contains { $0.caseInsensitiveCompare(model) == .orderedSame }
            if !matched {
                let preview = ids.prefix(6).joined(separator: ", ")
                let suffix = ids.count > 6 ? "…" : ""
                throw TranslationError.server(
                    status: 404,
                    message: "当前模型「\(model)」不在服务列表中。可用示例：\(preview)\(suffix)"
                )
            }
        }

        // Hard check: same path + same provider payload as recording / translation.
        try await probeChatCompletion(
            url: chatURL, model: model, apiKey: apiKey, profile: profile
        )
        return "翻译模型可用：\(model)（\(profile.kind.label)）"
    }

    private func fetchModelIDs(
        from modelsURL: URL,
        apiKey: String,
        profile: LLMProviderProfile
    ) async throws -> [String] {
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 12
        Self.applyBearerIfNeeded(apiKey, to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = HTTPErrorBody.summarize(data)
            throw TranslationError.server(
                status: http.statusCode,
                message: profile.authHint(status: http.statusCode, host: modelsURL.host, body: message)
            )
        }
        guard let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            throw TranslationError.invalidResponse
        }
        return decoded.data.map(\.id)
    }

    /// Minimal non-streaming completion — verifies inference auth, not just model listing.
    private func probeChatCompletion(
        url: URL,
        model: String,
        apiKey: String,
        profile: LLMProviderProfile
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyBearerIfNeeded(apiKey, to: &request)

        let probe = profile.probeSampling
        let payload = profile.chatCompletionPayload(
            model: model,
            messages: [["role": "user", "content": "ping"]],
            temperature: probe.temperature,
            topP: probe.topP,
            maxTokens: probe.maxTokens
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = HTTPErrorBody.summarize(data)
            throw TranslationError.server(
                status: http.statusCode,
                message: profile.authHint(status: http.statusCode, host: url.host, body: message)
            )
        }
    }

    static func applyBearerIfNeeded(_ apiKey: String, to request: inout URLRequest) {
        guard let authorization = EndpointSecurity.bearerHeader(apiKey: apiKey) else { return }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    /// Resolve provider profile then build the chat body (shared by translate + format).
    static func chatCompletionPayload(
        model: String,
        messages: [[String: String]],
        temperature: Double,
        topP: Double,
        maxTokens: Int,
        endpoint: String? = nil
    ) -> [String: Any] {
        LLMProviderProfile.resolve(endpoint: endpoint, model: model).chatCompletionPayload(
            model: model,
            messages: messages,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens
        )
    }

    /// Append actionable guidance for auth / unsupported-parameter failures.
    static func authHintIfNeeded(
        status: Int,
        host: String?,
        body: String,
        model: String = "",
        endpoint: String? = nil
    ) -> String {
        LLMProviderProfile.resolve(endpoint: endpoint, model: model)
            .authHint(status: status, host: host, body: body)
    }

    func translate(
        text: String,
        configuration: TranslationConfiguration,
        onUsage: (@Sendable (TokenUsage) -> Void)? = nil
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await performTranslation(
                    text: text, configuration: configuration, onUsage: onUsage
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                throw TranslationError.timedOut(seconds: Self.requestTimeoutSeconds)
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw TranslationError.invalidResponse
            }
            return result
        }
    }

    private func performTranslation(
        text: String,
        configuration: TranslationConfiguration,
        onUsage: (@Sendable (TokenUsage) -> Void)?
    ) async throws -> String {
        guard let url = URL(string: configuration.endpoint) else {
            throw TranslationError.invalidEndpoint
        }
        guard EndpointSecurity.allowsCredentialTransmission(to: url, apiKey: configuration.apiKey) else {
            throw TranslationError.insecureEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(Self.requestTimeoutSeconds)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyBearerIfNeeded(configuration.apiKey, to: &request)

        let styleBlock = configuration.styleHint.isEmpty
            ? ""
            : "\nStyle requirements:\n\(configuration.styleHint)"
        let messages: [[String: String]]
        let maxTokens: Int
        let temperature: Double
        switch configuration.task {
        case .smartRoute:
            var systemPrompt = configuration.customSystemPrompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !systemPrompt.isEmpty else {
                throw TranslationError.promptCompile("智能路由需要自定义 System Prompt，请在「翻译与整理」中填写。")
            }
            if !configuration.roleContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                systemPrompt += "\n\n" + configuration.roleContextPrompt
            }
            messages = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
            maxTokens = 4096
            temperature = 0.3
        case .optimizePrompt:
            // Stage 1 only: LLM extracts Prompt IR JSON. Stage 2 is local.
            let languageDirective = configuration.styleHint.isEmpty
                ? "Write all IR string fields in the same language as the source dictation."
                : configuration.styleHint
            messages = TranslationClient.appendingRoleContext(
                to: PromptCompiler.irExtractionMessages(
                sourceText: text,
                languageDirective: languageDirective
                ), role: configuration.roleContextPrompt
            )
            maxTokens = 2048
            temperature = 0.2
            case .translate:
            messages = [
                [
                    "role": "system",
                    "content": Self.appendingRoleContext(to: Self.withCustomSystemPrompt("""
                    You are a translation engine, not a reasoning assistant.
                    Translate the following text into \(configuration.targetLanguage).
                    Rules:
                    - Output the translation only — fully in \(configuration.targetLanguage).
                    - Do not leave the main sentence(s) in the source language.
                    - If the source is English and the target is Chinese, every narrative sentence must be Chinese.
                    - Preserve technical identifiers, product names, paths, and code-like tokens.
                    - Do not write Thinking Process, analysis, drafts, notes, or explanations.
                    - Do not use markdown or quotation marks around the result.
                    \(styleBlock)
                    """, custom: configuration.customSystemPrompt), role: configuration.roleContextPrompt)
                ],
                [
                    "role": "user",
                    "content": "Translate into \(configuration.targetLanguage) now. Source:\n\n\(text)"
                ]
            ]
            maxTokens = 1024
            temperature = 0.1
        }
        let effectiveMessages = configuration.task == .optimizePrompt
            ? Self.appendingCustomSystemPrompt(
                to: messages, custom: configuration.customSystemPrompt
            )
            : messages
        let model = Self.sanitizeModelName(configuration.model)
        if configuration.task == .translate,
           configuration.targetLanguage == "Japanese",
           !Self.supportsJapaneseNaturalTranslation(model: model) {
            throw TranslationError.japaneseModelTooOld
        }
        let payload = Self.chatCompletionPayload(
            model: model,
            messages: effectiveMessages,
            temperature: temperature,
            topP: 0.8,
            maxTokens: maxTokens,
            endpoint: configuration.endpoint
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = HTTPErrorBody.summarize(data)
            throw TranslationError.server(
                status: http.statusCode,
                message: Self.authHintIfNeeded(
                    status: http.statusCode,
                    host: url.host,
                    body: message,
                    model: model,
                    endpoint: configuration.endpoint
                )
            )
        }
        guard let chat = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let message = chat.choices.first?.message else {
            throw TranslationError.invalidResponse
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let usage = TokenUsage.parse(object["usage"]) {
            onUsage?(usage)
        }

        let raw = message.content ?? ""
        if configuration.task == .smartRoute {
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { throw TranslationError.emptyText }
            return cleaned
        }
        if configuration.task == .optimizePrompt {
            // Stage 1 cleanup → parse IR → Stage 2 local Target Adapter
            let irText = Self.sanitizeIRModelOutput(raw)
            do {
                return try PromptCompiler.compile(irRaw: irText, target: configuration.promptTarget)
            } catch let error as PromptCompilerError {
                throw TranslationError.promptCompile(error.localizedDescription)
            } catch {
                throw TranslationError.promptCompile(error.localizedDescription)
            }
        }

        let cleaned = Self.sanitizeModelOutput(raw)
        guard !cleaned.isEmpty else { throw TranslationError.emptyText }
        return cleaned
    }

    static func withCustomSystemPrompt(_ base: String, custom: String) -> String {
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return "\(base)\n\n用户自定义 System Prompt（在不违背上述任务与安全边界的前提下遵守）：\n\(trimmed)"
    }

    static func appendingCustomSystemPrompt(
        to messages: [[String: String]], custom: String
    ) -> [[String: String]] {
        guard !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return messages
        }
        var result = messages
        if let index = result.firstIndex(where: { $0["role"] == "system" }) {
            result[index]["content"] = withCustomSystemPrompt(
                result[index]["content"] ?? "", custom: custom
            )
        } else {
            result.insert(["role": "system", "content": custom], at: 0)
        }
        return result
    }

    static func appendingRoleContext(to base: String, role: String) -> String {
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return "\(base)\n\n\(trimmed)"
    }

    static func appendingRoleContext(to messages: [[String: String]], role: String) -> [[String: String]] {
        guard !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return messages }
        var result = messages
        if let index = result.firstIndex(where: { $0["role"] == "system" }) {
            result[index]["content"] = appendingRoleContext(to: result[index]["content"] ?? "", role: role)
        } else {
            result.insert(["role": "system", "content": role], at: 0)
        }
        return result
    }

    /// Light cleanup before IR JSON parse — keep braces/quotes intact.
    static func sanitizeIRModelOutput(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagPatterns = [
            #"<think>[\s\S]*?</think>"#,
            #"<thinking>[\s\S]*?</thinking>"#,
            #"<reason>[\s\S]*?</reason>"#
        ]
        for pattern in tagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove a single outer markdown fence if the model wrapped the whole prompt.
    static func stripOuterCodeFence(_ text: String) -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.hasPrefix("```") else { return result }
        var lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2, lines[0].hasPrefix("```") else { return result }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        lines.removeFirst()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip reasoning dumps that Qwen3.5 may still emit even after disable flags.
    static func sanitizeModelOutput(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let tagPatterns = [
            #"<think>[\s\S]*?</think>"#,
            #"<thinking>[\s\S]*?</thinking>"#,
            #"<reason>[\s\S]*?</reason>"#
        ]
        for pattern in tagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        let thinkingMarkers = [
            "Thinking Process:",
            "思考过程：",
            "思考過程：",
            "Analysis:",
            "Drafting Translations:",
            "Final Polish:"
        ]
        let looksLikeThinking = thinkingMarkers.contains { marker in
            result.localizedCaseInsensitiveContains(marker)
        } || result.hasPrefix("1.  **Analyze") || result.hasPrefix("1. **Analyze")

        if looksLikeThinking {
            if let extracted = extractMarkedFinalTranslation(from: result) {
                return extracted
            }
            // Bare reasoning dump with no explicit final line — treat as unusable.
            return ""
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMarkedFinalTranslation(from text: String) -> String? {
        let markers = [
            "Final translation:",
            "Final version:",
            "Final choice:",
            "Translation:",
            "Output:",
            "最终翻译：",
            "译文："
        ]

        let lowered = text.lowercased()
        for marker in markers {
            guard let range = lowered.range(of: marker.lowercased()) else { continue }
            let after = text[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let firstParagraph = after.split(separator: "\n", omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleaned = firstParagraph
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlausibleTranslation(cleaned) {
                return cleaned
            }
        }
        return nil
    }

    private static func isPlausibleTranslation(_ line: String) -> Bool {
        guard line.count >= 8, line.count <= 500 else { return false }
        let lowered = line.lowercased()
        let banned = [
            "thinking process",
            "analyze the",
            "drafting",
            "draft 1",
            "draft 2",
            "draft 3",
            "refining for",
            "constraints:",
            "final polish",
            "selection:",
            "alternative:",
            "re-evaluating",
            "okay, i will",
            "okay, final",
            "wait, one more",
            "wait, looking"
        ]
        if banned.contains(where: { lowered.contains($0) }) { return false }
        if lowered.hasPrefix("1.") || lowered.hasPrefix("2.") || lowered.hasPrefix("3.") {
            return false
        }
        if lowered.hasPrefix("*") || lowered.hasPrefix("-") {
            return false
        }
        return true
    }
}
