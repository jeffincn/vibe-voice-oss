import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum SystemTextComposer {
    enum ComposerError: LocalizedError {
        case unavailable
        var errorDescription: String? { "iOS 26 本机语言模型当前不可用" }
    }

    static var reasoningInstructions: String {
        """
        你是一个谨慎的对话溯因推理器。只根据用户提供的对话推断最可能的隐藏背景，不能把猜测写成确定事实。必须区分对话中的直接证据、合理推断和不确定性。只返回 JSON，不要 Markdown，不要补写对话。JSON 字段必须是：hidden_behavior（字符串）、evidence（字符串数组）、motivation（字符串）、confidence（0 到 1 的数字）、uncertainties（字符串数组）。
        """
    }

    static func reasoningPrompt(for dialogue: String) -> String {
        """
        请分析以下对话，回答：
        1. 角色 B/乙试图隐藏的真实行为是什么？
        2. 角色 A/甲通过哪些异常线索逐步发现真相？
        3. 角色 B/乙隐瞒的心理动机是什么？
        只使用对话本身，不依赖外界事实。列出支持结论的具体证据；对明显矛盾、无法确定或存在不确定性的部分放入 uncertainties。

        对话：
        \(dialogue)
        """
    }

    /// Whole-sentence enhancement is deliberately app/playground-only. The
    /// keyboard keeps keystrokes on Rime + Core ML so iOS 17/18 stay offline,
    /// predictable, and within extension memory limits.
    static func refine(_ text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw ComposerError.unavailable
            }
            let session = LanguageModelSession(
                instructions: "你是输入法整句润色器。只返回润色后的文本，不要解释，不要添加引号。保留原意和语言。"
            )
            let response = try await session.respond(
                to: "请润色这句话，保持简洁自然：\n\(text)"
            )
            return response.content
        }
        #endif
        throw ComposerError.unavailable
    }

    /// App/Playground-only abductive reasoning. The keyboard extension does
    /// not call this path on each keystroke: it remains Rime + Core ML.
    static func inferHiddenContext(_ dialogue: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw ComposerError.unavailable
            }
            let session = LanguageModelSession(instructions: reasoningInstructions)
            let response = try await session.respond(to: reasoningPrompt(for: dialogue))
            return response.content
        }
        #endif
        throw ComposerError.unavailable
    }
}
