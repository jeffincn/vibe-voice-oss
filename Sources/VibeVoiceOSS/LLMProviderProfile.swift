import Foundation

/// Known LLM wire dialects behind an OpenAI-compatible `/v1/chat/completions` URL.
///
/// "OpenAI-compatible" only guarantees path + Bearer auth + core fields. Each vendor
/// extends or rejects extras differently — keep those differences here, not in callers.
enum LLMProviderKind: String, CaseIterable, Identifiable, Sendable {
    case openaiCompatible
    case qwen
    case nvidiaNemotron

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openaiCompatible: "OpenAI 兼容"
        case .qwen: "Qwen"
        case .nvidiaNemotron: "NVIDIA Nemotron"
        }
    }

    var caption: String {
        switch self {
        case .openaiCompatible:
            "仅发送标准 OpenAI 字段（model / messages / temperature / top_p / max_tokens）。"
        case .qwen:
            "关闭思维链：enable_thinking=false + chat_template_kwargs。"
        case .nvidiaNemotron:
            "按 build.nvidia.com 官方规则发送 chat_template_kwargs + reasoning_budget（禁止顶层 enable_thinking）。"
        }
    }
}

/// Stateless adapter that builds chat payloads and auth/validation hints for one provider.
struct LLMProviderProfile: Sendable, Equatable {
    let kind: LLMProviderKind

    // MARK: - Resolution

    /// Prefer model-id heuristics; fall back to host hints for NVIDIA auth messaging only.
    static func resolve(endpoint: String? = nil, model: String) -> LLMProviderProfile {
        let id = model.lowercased()
        if id.contains("nemotron") {
            return LLMProviderProfile(kind: .nvidiaNemotron)
        }
        if id.contains("qwen") {
            return LLMProviderProfile(kind: .qwen)
        }
        // Non-Nemotron models on integrate.api.nvidia.com still use the vanilla OpenAI body.
        _ = endpoint
        return LLMProviderProfile(kind: .openaiCompatible)
    }

    static func looksLikeNVIDIA(host: String?, body: String = "") -> Bool {
        let hostLower = (host ?? "").lowercased()
        return hostLower.contains("nvidia")
            || hostLower.contains("nvcf")
            || body.localizedCaseInsensitiveContains("nvapi")
            || body.localizedCaseInsensitiveContains("integrate.api")
    }

    // MARK: - Sampling defaults for connection probes

    struct ProbeSampling: Sendable {
        let temperature: Double
        let topP: Double
        let maxTokens: Int
    }

    var probeSampling: ProbeSampling {
        switch kind {
        case .nvidiaNemotron:
            ProbeSampling(temperature: 1.0, topP: 0.95, maxTokens: 64)
        case .qwen, .openaiCompatible:
            ProbeSampling(temperature: 0, topP: 1.0, maxTokens: 1)
        }
    }

    // MARK: - Request body

    /// Build a chat-completions JSON object for this provider.
    func chatCompletionPayload(
        model: String,
        messages: [[String: String]],
        temperature: Double,
        topP: Double,
        maxTokens: Int
    ) -> [String: Any] {
        switch kind {
        case .openaiCompatible:
            return basePayload(
                model: model,
                messages: messages,
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens
            )

        case .qwen:
            var payload = basePayload(
                model: model,
                messages: messages,
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens
            )
            // Suppress CoT on Qwen chat templates (local oMLX / DashScope-style).
            payload["enable_thinking"] = false
            payload["chat_template_kwargs"] = ["enable_thinking": false]
            return payload

        case .nvidiaNemotron:
            // Official Integrate sample: temperature≈1, top_p=0.95, nested thinking only.
            let effectiveTemperature = max(temperature, 0.6)
            let effectiveTopP = max(topP, 0.95)
            let budget = Self.nemotronReasoningBudget(forMaxTokens: maxTokens)
            let effectiveMaxTokens = max(maxTokens, budget + maxTokens)
            var payload = basePayload(
                model: model,
                messages: messages,
                temperature: effectiveTemperature,
                topP: effectiveTopP,
                maxTokens: effectiveMaxTokens
            )
            payload["chat_template_kwargs"] = ["enable_thinking": true]
            payload["reasoning_budget"] = budget
            // Never set top-level enable_thinking — Integrate returns Validation: Unsupported.
            return payload
        }
    }

    /// Reasoning token budget for Nemotron Integrate (`extra_body.reasoning_budget`).
    static func nemotronReasoningBudget(forMaxTokens maxTokens: Int) -> Int {
        min(4096, max(256, maxTokens))
    }

    private func basePayload(
        model: String,
        messages: [[String: String]],
        temperature: Double,
        topP: Double,
        maxTokens: Int
    ) -> [String: Any] {
        [
            "model": model,
            "temperature": temperature,
            "top_p": topP,
            "max_tokens": maxTokens,
            "messages": messages
        ]
    }

    // MARK: - Error hints

    func authHint(status: Int, host: String?, body: String) -> String {
        let looksNVIDIA = Self.looksLikeNVIDIA(host: host, body: body)

        if status == 400,
           body.localizedCaseInsensitiveContains("unsupported")
            || body.localizedCaseInsensitiveContains("validation") {
            var hint = body
            switch kind {
            case .nvidiaNemotron:
                hint += " — NVIDIA Nemotron 需 chat_template_kwargs.enable_thinking"
                    + " + reasoning_budget（禁止顶层 enable_thinking）。当前 Profile：\(kind.label)。"
            case .qwen:
                hint += " — 当前按 Qwen Profile 发送了 thinking 控制字段；若服务端不支持，请换用 OpenAI 兼容模型名。"
            case .openaiCompatible:
                if looksNVIDIA {
                    hint += " — NVIDIA 拒绝了请求中的扩展字段。若使用 Nemotron，请确认模型名含 nemotron 以便自动切换 Profile。"
                } else {
                    hint += " — 服务端不接受请求中的扩展参数。"
                }
            }
            return hint
        }

        guard status == 401 || status == 403 else { return body }
        var hint = body
        if looksNVIDIA {
            hint += " — NVIDIA：模型列表可达不等于可推理。请确认 API Key 对 Public API Endpoints / 该模型有调用权限，或在 build.nvidia.com 重新生成 Key 后重试。"
        } else {
            hint += " — 请确认 LLM API Key 正确，且对该模型有推理权限（仅「模型列表」通过不够）。"
        }
        return hint
    }
}
