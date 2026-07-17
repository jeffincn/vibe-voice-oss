import Foundation

struct TranslationConfiguration: Sendable {
    let endpoint: String
    let model: String
    let targetLanguage: String
    let styleHint: String
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
    case timedOut
    case promptCompile(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "翻译接口地址无效。"
        case let .server(status, message): "翻译模型返回 HTTP \(status)：\(message)"
        case .invalidResponse: "翻译模型返回了无法解析的响应。"
        case .emptyText: "翻译完成，但返回文本为空。"
        case .timedOut: "翻译超过 60 秒，已自动中断。"
        case let .promptCompile(detail): "Prompt 编译失败：\(detail)"
        }
    }
}

struct TranslationClient: Sendable {
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

    /// Derive OpenAI `/v1/models` from a chat-completions URL (`…/v1/chat/completions`).
    /// Mirrors ASR: strip two trailing segments (`chat` + `completions`), then append `models`.
    static func modelsProbeURL(from chatCompletionsURL: URL) -> URL {
        chatCompletionsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models")
    }

    /// Probe `/v1/models` from a chat-completions URL and confirm `model` is listed.
    func checkServer(configuration: TranslationConfiguration) async throws -> String {
        let model = Self.sanitizeModelName(configuration.model)
        guard let chatURL = URL(string: configuration.endpoint) else {
            throw TranslationError.invalidEndpoint
        }
        let modelsURL = Self.modelsProbeURL(from: chatURL)
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 12
        if !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw TranslationError.server(status: http.statusCode, message: message)
        }

        guard let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return "翻译接口可达（\(modelsURL.host ?? "server")），但无法解析模型列表"
        }
        let ids = decoded.data.map(\.id)
        let matched = ids.contains { $0.caseInsensitiveCompare(model) == .orderedSame }
        if matched {
            return "翻译模型可用：\(model)"
        }
        if model.isEmpty {
            throw TranslationError.server(status: 404, message: "未配置翻译模型名。")
        }
        let preview = ids.prefix(6).joined(separator: ", ")
        let suffix = ids.count > 6 ? "…" : ""
        throw TranslationError.server(
            status: 404,
            message: "当前模型「\(model)」不在服务列表中。可用示例：\(preview)\(suffix)"
        )
    }

    func translate(text: String, configuration: TranslationConfiguration) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await performTranslation(text: text, configuration: configuration)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw TranslationError.timedOut
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
        configuration: TranslationConfiguration
    ) async throws -> String {
        guard let url = URL(string: configuration.endpoint) else {
            throw TranslationError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let styleBlock = configuration.styleHint.isEmpty
            ? ""
            : "\nStyle requirements:\n\(configuration.styleHint)"
        let messages: [[String: String]]
        let maxTokens: Int
        let temperature: Double
        switch configuration.task {
        case .optimizePrompt:
            // Stage 1 only: LLM extracts Prompt IR JSON. Stage 2 is local.
            let languageDirective = configuration.styleHint.isEmpty
                ? "Write all IR string fields in the same language as the source dictation."
                : configuration.styleHint
            messages = PromptCompiler.irExtractionMessages(
                sourceText: text,
                languageDirective: languageDirective
            )
            maxTokens = 2048
            temperature = 0.2
            case .translate:
            messages = [
                [
                    "role": "system",
                    "content": """
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
                    """
                ],
                [
                    "role": "user",
                    "content": "Translate into \(configuration.targetLanguage) now. Source:\n\n\(text)"
                ],
                // Prefill closed think block — reliable fallback when template kwargs are ignored.
                [
                    "role": "assistant",
                    "content": "<think>\n</think>\n"
                ]
            ]
            maxTokens = 1024
            temperature = 0.1
        }
        let payload: [String: Any] = [
            "model": Self.sanitizeModelName(configuration.model),
            "temperature": temperature,
            "top_p": 0.8,
            "max_tokens": maxTokens,
            "enable_thinking": false,
            "chat_template_kwargs": [
                "enable_thinking": false
            ],
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw TranslationError.server(status: http.statusCode, message: message)
        }
        guard let chat = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let message = chat.choices.first?.message else {
            throw TranslationError.invalidResponse
        }

        let raw = message.content ?? ""
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
