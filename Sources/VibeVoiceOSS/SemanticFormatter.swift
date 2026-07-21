import Foundation

/// Intensity of semantic reformatting. `auto` resolves from transcript length.
enum StructureIntensity: String, CaseIterable, Identifiable, Sendable {
    case auto
    case clean
    case ultraConcise = "ultra_concise"
    case structured
    case rewrite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: L10n.t(.intensityAuto)
        case .clean: L10n.t(.intensityClean)
        case .ultraConcise: L10n.t(.intensityUltraConcise)
        case .structured: L10n.t(.intensityStructured)
        case .rewrite: L10n.t(.intensityRewrite)
        }
    }

    var caption: String {
        switch self {
        case .auto: L10n.t(.intensityAutoCaption)
        case .clean: L10n.t(.intensityCleanCaption)
        case .ultraConcise: L10n.t(.intensityUltraConciseCaption)
        case .structured: L10n.t(.intensityStructuredCaption)
        case .rewrite: L10n.t(.intensityRewriteCaption)
        }
    }
}

/// Resolved processing mode after auto-selection.
enum StructureMode: String, Sendable {
    case clean
    case ultraConcise = "ultra_concise"
    case structured
    case rewrite
}

struct SemanticFormatterConfiguration: Sendable {
    let endpoint: String
    let model: String
    let apiKey: String
    let mode: StructureMode
    var customSystemPrompt: String = ""
    /// When set, structured cleanup must emit this language (e.g. Simplified Chinese).
    var outputLanguageDirective: String? = nil
    /// Decorative emoji in structured / ultra / rewrite layouts. Default off.
    var useEmoji: Bool = false
}

enum SemanticFormatterError: LocalizedError {
    case invalidEndpoint
    case server(status: Int, message: String)
    case invalidResponse
    case emptyText
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "结构化整理接口地址无效。"
        case let .server(status, message): "整理模型返回 HTTP \(status)：\(message)"
        case .invalidResponse: "整理模型返回了无法解析的响应。"
        case .emptyText: "整理完成，但返回文本为空。"
        case let .timedOut(seconds):
            "结构化整理超过 \(seconds) 秒，已自动中断。请检查百炼模型限流、上下文长度或缩短输入后重试。"
        }
    }
}

enum SemanticFormatter {
    struct FewShotExample: Sendable {
        let input: String
        let output: String
    }

    /// Pick intensity from character count when user leaves mode on Auto.
    /// - <20 → clean
    /// - 20…100 → clean (short chat) unless multi-paragraph cues → structured
    /// - >100 → structured
    /// `ultraConcise` / `rewrite` are never chosen automatically.
    static func resolveMode(for text: String, intensity: StructureIntensity) -> StructureMode {
        switch intensity {
        case .clean: return .clean
        case .ultraConcise: return .ultraConcise
        case .structured: return .structured
        case .rewrite: return .rewrite
        case .auto:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let count = trimmed.count
            if count < 20 { return .clean }
            if count > 100 { return .structured }
            // Mid range: prefer clean for chat-like single sentences;
            // bump to structured when there are clear multi-item / section cues.
            if looksLikeMultiItem(trimmed) { return .structured }
            return .clean
        }
    }

    private static func looksLikeMultiItem(_ text: String) -> Bool {
        let cues = ["第一", "第二", "第三", "首先", "其次", "另外", "还有", "待办", "步骤", "1.", "2.", "①", "②"]
        let hitCount = cues.reduce(0) { partial, cue in
            partial + (text.contains(cue) ? 1 : 0)
        }
        let newlines = text.filter { $0.isNewline }.count
        return hitCount >= 2 || newlines >= 2
    }

    /// Shared chat-reading layout with decorative emoji (when enabled).
    private static let chatLayoutRulesWithEmoji = """
    对话阅读排版（内容整理 / 超精简 / 深度整理均必须遵守）：
    - 短段 + 空行：避免大段堆砌；一句一事更易扫读。
    - 长文换行：正文超过约 100 字且含多句时，必须用换行拆开；尽量让每一行/每一句约 20 个汉字，一句一事、一句一行。
    - 语义相关的短句之间用空行分段；清单仍用 - 或编号，每条一行。
    - 不要为凑行宽硬拆专有名词、路径、代码标识符或英文专名。
    - 必须使用修饰性 emoji：每个分区标题或关键要点行前加 1 个 macOS / 聊天输入法常规 Unicode emoji（如 ✅ 📌 💡 ⚠️ 📝 🎯 ✨ 🚀 🔍 💬）。
    - 纯文字、毫无 emoji 的输出视为不合格；至少出现 1–3 个 emoji，让读起来更轻松有趣。
    - 不要用 [NOTE]、[TODO]、[OK] 这类方括号单词标签代替 emoji。
    - 不要整行刷 emoji，也不要在每个清单条目前都塞 emoji。
    """

    /// Same layout without decorative emoji (default).
    private static let chatLayoutRulesPlain = """
    对话阅读排版（内容整理 / 超精简 / 深度整理均必须遵守）：
    - 短段 + 空行：避免大段堆砌；一句一事更易扫读。
    - 长文换行：正文超过约 100 字且含多句时，必须用换行拆开；尽量让每一行/每一句约 20 个汉字，一句一事、一句一行。
    - 语义相关的短句之间用空行分段；清单仍用 - 或编号，每条一行。
    - 不要为凑行宽硬拆专有名词、路径、代码标识符或英文专名。
    - 可用简短中文小标题（如「结论」「待办」「问题」），不要使用 emoji。
    - 不要用 [NOTE]、[TODO]、[OK] 这类方括号单词标签。
    - 不要为装饰而堆砌符号。
    """

    private static func chatLayoutRules(useEmoji: Bool) -> String {
        useEmoji ? chatLayoutRulesWithEmoji : chatLayoutRulesPlain
    }

    /// Layout few-shots with emoji.
    static let layoutFewShotsStructuredEmoji: [FewShotExample] = [
        FewShotExample(
            input: "嗯那个明天下午三点跟产品开个会吧，主要聊一下首页改版，还有就是埋点可能要补一下，另外设计稿我可能周五才能给到你们，你们先看看现有的交互。",
            output: """
            📌 明天下午 3 点，和产品开首页改版会。

            🎯 讨论重点：
            - 首页改版方案
            - 埋点是否需要补齐（待确认）

            ⚠️ 设计稿可能周五才能给到；可先看现有交互。
            """
        ),
        FewShotExample(
            input: "今天把登录超时修了，然后导出 CSV 还没做，哦对了文档也要更新一下，接口那块小王说可能下周才有空。",
            output: """
            ✅ 登录超时已修好。

            📝 待办：
            - 导出 CSV
            - 更新文档

            💡 接口改动：小王可能下周才有空。
            """
        ),
        FewShotExample(
            input: "我觉得这个页面加载有点慢，用户一进来就转圈，可能是接口慢也可能是前端渲染问题，你帮我看看吧。",
            output: """
            🔍 页面一进就转圈，加载偏慢。

            💬 可能原因（待确认）：
            - 接口慢
            - 前端渲染慢

            ✨ 请先对照现有实现排查，再给结论。
            """
        ),
    ]

    static let layoutFewShotsStructuredPlain: [FewShotExample] = [
        FewShotExample(
            input: "嗯那个明天下午三点跟产品开个会吧，主要聊一下首页改版，还有就是埋点可能要补一下，另外设计稿我可能周五才能给到你们，你们先看看现有的交互。",
            output: """
            明天下午 3 点，和产品开首页改版会。

            讨论重点：
            - 首页改版方案
            - 埋点是否需要补齐（待确认）

            注意：设计稿可能周五才能给到；可先看现有交互。
            """
        ),
        FewShotExample(
            input: "今天把登录超时修了，然后导出 CSV 还没做，哦对了文档也要更新一下，接口那块小王说可能下周才有空。",
            output: """
            登录超时已修好。

            待办：
            - 导出 CSV
            - 更新文档

            接口改动：小王可能下周才有空。
            """
        ),
        FewShotExample(
            input: "我觉得这个页面加载有点慢，用户一进来就转圈，可能是接口慢也可能是前端渲染问题，你帮我看看吧。",
            output: """
            页面一进就转圈，加载偏慢。

            可能原因（待确认）：
            - 接口慢
            - 前端渲染慢

            请先对照现有实现排查，再给结论。
            """
        ),
    ]

    /// Backward-compatible alias (emoji variants).
    static var layoutFewShotsStructured: [FewShotExample] { layoutFewShotsStructuredEmoji }

    static let layoutFewShotsUltraEmoji: [FewShotExample] = [
        FewShotExample(
            input: "嗯那个明天下午三点跟产品开个会吧，主要聊一下首页改版，还有就是埋点可能要补一下，另外设计稿我可能周五才能给到你们，你们先看看现有的交互。",
            output: """
            📌 明天下午 3 点 · 首页改版会

            🎯 改版方案 · 埋点是否补齐（待确认）

            ⚠️ 设计稿或周五才到；先看现有交互
            """
        ),
        FewShotExample(
            input: "今天把登录超时修了，然后导出 CSV 还没做，哦对了文档也要更新一下，接口那块小王说可能下周才有空。",
            output: """
            ✅ 登录超时已修

            📝 CSV 导出 · 文档更新

            💡 接口：小王或下周才有空
            """
        ),
        FewShotExample(
            input: "我觉得这个页面加载有点慢，用户一进来就转圈，可能是接口慢也可能是前端渲染问题，你帮我看看吧。",
            output: """
            🔍 进页转圈 · 加载慢

            💬 可能：接口 / 前端渲染（待确认）

            ✨ 先查现有实现再下结论
            """
        ),
    ]

    static let layoutFewShotsUltraPlain: [FewShotExample] = [
        FewShotExample(
            input: "嗯那个明天下午三点跟产品开个会吧，主要聊一下首页改版，还有就是埋点可能要补一下，另外设计稿我可能周五才能给到你们，你们先看看现有的交互。",
            output: """
            明天下午 3 点 · 首页改版会

            改版方案 · 埋点是否补齐（待确认）

            设计稿或周五才到；先看现有交互
            """
        ),
        FewShotExample(
            input: "今天把登录超时修了，然后导出 CSV 还没做，哦对了文档也要更新一下，接口那块小王说可能下周才有空。",
            output: """
            登录超时已修

            CSV 导出 · 文档更新

            接口：小王或下周才有空
            """
        ),
        FewShotExample(
            input: "我觉得这个页面加载有点慢，用户一进来就转圈，可能是接口慢也可能是前端渲染问题，你帮我看看吧。",
            output: """
            进页转圈 · 加载慢

            可能：接口 / 前端渲染（待确认）

            先查现有实现再下结论
            """
        ),
    ]

    static var layoutFewShotsUltra: [FewShotExample] { layoutFewShotsUltraEmoji }

    static let layoutFewShotsRewriteEmoji: [FewShotExample] = [
        FewShotExample(
            input: "嗯那个明天下午三点跟产品开个会吧，主要聊一下首页改版，还有就是埋点可能要补一下，另外设计稿我可能周五才能给到你们，你们先看看现有的交互。",
            output: """
            📌 会议安排

            明天下午 3 点与产品同步首页改版。

            🎯 议程：改版方案；埋点是否补齐（待确认）。

            ⚠️ 设计稿可能周五交付，此前可先审阅现有交互。
            """
        ),
        FewShotExample(
            input: "我觉得这个页面加载有点慢，用户一进来就转圈，可能是接口慢也可能是前端渲染问题，你帮我看看吧。",
            output: """
            🔍 问题现象

            用户进入页面后持续转圈，整体加载偏慢。

            💬 待核实方向：接口耗时，或前端渲染瓶颈。

            ✨ 请基于现有实现定位后再给出结论。
            """
        ),
    ]

    static let layoutFewShotsRewritePlain: [FewShotExample] = [
        FewShotExample(
            input: "嗯那个明天下午三点跟产品开个会吧，主要聊一下首页改版，还有就是埋点可能要补一下，另外设计稿我可能周五才能给到你们，你们先看看现有的交互。",
            output: """
            会议安排

            明天下午 3 点与产品同步首页改版。

            议程：改版方案；埋点是否补齐（待确认）。

            设计稿可能周五交付，此前可先审阅现有交互。
            """
        ),
        FewShotExample(
            input: "我觉得这个页面加载有点慢，用户一进来就转圈，可能是接口慢也可能是前端渲染问题，你帮我看看吧。",
            output: """
            问题现象

            用户进入页面后持续转圈，整体加载偏慢。

            待核实方向：接口耗时，或前端渲染瓶颈。

            请基于现有实现定位后再给出结论。
            """
        ),
    ]

    static var layoutFewShotsRewrite: [FewShotExample] { layoutFewShotsRewriteEmoji }

    static func fewShots(for mode: StructureMode, useEmoji: Bool = false) -> [FewShotExample] {
        switch mode {
        case .clean:
            return []
        case .ultraConcise:
            return useEmoji ? layoutFewShotsUltraEmoji : layoutFewShotsUltraPlain
        case .structured:
            return useEmoji ? layoutFewShotsStructuredEmoji : layoutFewShotsStructuredPlain
        case .rewrite:
            return useEmoji ? layoutFewShotsRewriteEmoji : layoutFewShotsRewritePlain
        }
    }

    static func systemPrompt(
        for mode: StructureMode,
        outputLanguageDirective: String? = nil,
        useEmoji: Bool = false
    ) -> String {
        let shared = """
        你是一个语音内容整理助手。
        你的任务不是简单修改措辞，而是理解使用者真正想表达的内容，
        将口语化的语音转写整理成清晰、自然、有逻辑的书面内容。

        安全边界（必须遵守）：
        - 必须区分事实、决定、建议、倾向和不确定判断。
        - 不能把「可能、考虑、倾向、建议」改写成已经确定的结论。
        - 模型可以整理表达，但不能替用户改变决策。
        - 准确保留原意，不增加使用者没有表达的信息。
        - 不要解释你做了哪些修改。
        - 只输出整理完成的正文。
        - 使用 Markdown，但不要输出 Markdown 代码块。
        - 绝对不要在正文中写出任何元指令、提示词或语言要求标签
          （例如「输出语言」「要求的输出语言」「REQUIRED OUTPUT LANGUAGE」及带方括号的同类说明）。
        """

        let languageBlock: String
        if let directive = outputLanguageDirective?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directive.isEmpty {
            languageBlock = """

            输出语言（最高优先级，必须遵守；仅作内部约束，禁止写入正文）：
            \(directive)
            """
        } else {
            languageBlock = """

            输出语言（仅作内部约束，禁止写入正文）：与原始转写保持同一语言；不要擅自翻译。
            """
        }

        switch mode {
        case .clean:
            return """
            \(shared)
            \(languageBlock)

            当前强度：轻度整理（clean）
            只做：
            - 标点与断句修正；
            - 修复语音识别造成的明显错词；
            - 删除无实际意义的口头语（嗯、啊、就是、然后、那个、我觉得吧等）；
            - 合并明显重复或自我修正的表述，以最后确认的意思为准；
            - 基本分段。
            不要调整论述顺序，不要加标题，不要改成清单或步骤，不要大幅改写措辞。
            一般不加 emoji；除非原文本身已带 emoji，可原样保留。
            """
        case .ultraConcise:
            let layoutClose = useEmoji
                ? "排版仍按上面的对话阅读习惯与样例：短段、空行，且必须带修饰性 emoji。"
                : "排版仍按上面的对话阅读习惯与样例：短段、空行；不要使用 emoji。"
            return """
            \(shared)
            \(languageBlock)

            \(chatLayoutRules(useEmoji: useEmoji))

            当前强度：超精简（ultra_concise）
            这是在「内容整理」同一套排版习惯上的更严归纳规则，不是另一套排版系统。

            归纳规则（比内容整理更狠）：
            - 只保留关键事实、决定、待办与约束；
            - 删掉铺垫、口头复述、同义反复与无效细节；
            - 能一行说清就不要两行；能三点说清就不要七点；
            - 不确定处保留为「可能 / 待确认」，勿升格为定论。

            \(layoutClose)
            """
        case .structured:
            let formHints: String
            let closing: String
            if useEmoji {
                formHints = """
                输出形式由语义决定，不要机械地为所有内容增加「摘要、重点、结论」：
                - 简短消息 → 一至两个短段，行首仍可带 emoji；
                - 观点或分析 → emoji 主题 + 分段论述；
                - 多个并列事项 → emoji 小标题 + 项目符号清单；
                - 有先后关系 → emoji + 编号步骤；
                - 会议讨论 → ✅ 结论 / 📝 待办；
                - 技术内容 → 📌 背景 / 🔍 问题 / 💡 方案；
                - 混乱的灵感 → ✨ 主题分组。

                请严格对照样例：有分区就要有修饰性 emoji，不要输出干巴巴的纯文字。
                """
                closing = ""
            } else {
                formHints = """
                输出形式由语义决定，不要机械地为所有内容增加「摘要、重点、结论」：
                - 简短消息 → 一至两个短段；
                - 观点或分析 → 小标题 + 分段论述；
                - 多个并列事项 → 小标题 + 项目符号清单；
                - 有先后关系 → 编号步骤；
                - 会议讨论 → 结论 / 待办；
                - 技术内容 → 背景 / 问题 / 方案；
                - 混乱的灵感 → 主题分组。

                请严格对照样例：短段换行、可用中文小标题；不要使用 emoji。
                """
                closing = ""
            }
            return """
            \(shared)
            \(languageBlock)

            \(chatLayoutRules(useEmoji: useEmoji))

            当前强度：内容整理（structured）
            在轻度整理基础上，额外允许：
            - 理解段落与信息关系；
            - 根据语义关系调整表达顺序，但不得改变原有结论；
            - 使用标题、项目符号或编号步骤（仅在内容确实需要时）；
            - 提取明确的结论与待办（仅当原文已经表达这些内容时）。

            \(formHints)\(closing)
            """
        case .rewrite:
            let layoutClose = useEmoji
                ? "排版仍按对话阅读习惯与样例：短段、空行，且必须带修饰性 emoji。"
                : "排版仍按对话阅读习惯与样例：短段、空行；不要使用 emoji。"
            return """
            \(shared)
            \(languageBlock)

            \(chatLayoutRules(useEmoji: useEmoji))

            当前强度：深度整理（rewrite）
            在内容整理基础上，额外允许：
            - 更明显地改写措辞，使其更正式、紧凑；
            - 压缩冗余；
            - 重构文章组织；
            - 转换为适合邮件、报告或方案文档的表达。
            仍须保留原意与决策边界，不得把不确定说法写成定论。
            \(layoutClose)
            """
        }
    }

    static func userPrompt(
        transcript: String,
        mode: StructureMode? = nil,
        useEmoji: Bool = false
    ) -> String {
        var body = """
        原始语音转写如下：

        \(transcript)
        """
        if let mode, mode != .clean {
            if useEmoji {
                body += """


                请整理后输出：分区标题必须带常规修饰性 emoji；短段换行；长文尽量每行约 20 字、一句一行；不要纯文字干巴输出。
                """
            } else {
                body += """


                请整理后输出：短段换行；长文尽量每行约 20 字、一句一行；可用中文小标题；不要使用 emoji。
                """
            }
        }
        return body
    }

    /// Chat messages for the formatter, including layout few-shots when applicable.
    static func formattingMessages(
        transcript: String,
        mode: StructureMode,
        outputLanguageDirective: String? = nil,
        useEmoji: Bool = false,
        customSystemPrompt: String = ""
    ) -> [[String: String]] {
        var messages: [[String: String]] = [
            [
                "role": "system",
                "content": TranslationClient.withCustomSystemPrompt(systemPrompt(
                    for: mode,
                    outputLanguageDirective: outputLanguageDirective,
                    useEmoji: useEmoji
                ), custom: customSystemPrompt)
            ]
        ]

        for example in fewShots(for: mode, useEmoji: useEmoji) {
            messages.append([
                "role": "user",
                "content": userPrompt(transcript: example.input, mode: mode, useEmoji: useEmoji)
            ])
            messages.append([
                "role": "assistant",
                "content": example.output.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }

        messages.append([
            "role": "user",
            "content": userPrompt(transcript: transcript, mode: mode, useEmoji: useEmoji)
        ])
        return messages
    }
}

struct SemanticFormatterClient: Sendable {
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

    func format(
        text: String,
        configuration: SemanticFormatterConfiguration,
        onUsage: (@Sendable (TokenUsage) -> Void)? = nil
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await performFormat(text: text, configuration: configuration, onUsage: onUsage)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                throw SemanticFormatterError.timedOut(seconds: Self.requestTimeoutSeconds)
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw SemanticFormatterError.invalidResponse
            }
            return result
        }
    }

    private func performFormat(
        text: String,
        configuration: SemanticFormatterConfiguration,
        onUsage: (@Sendable (TokenUsage) -> Void)?
    ) async throws -> String {
        guard let url = URL(string: configuration.endpoint) else {
            throw SemanticFormatterError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(Self.requestTimeoutSeconds)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let temperature: Double
        let maxTokens: Int
        switch configuration.mode {
        case .clean:
            temperature = 0.2
            maxTokens = 1024
        case .ultraConcise:
            temperature = 0.25
            maxTokens = 1024
        case .structured:
            temperature = 0.35
            maxTokens = 2048
        case .rewrite:
            temperature = 0.45
            maxTokens = 3072
        }

        let payload: [String: Any] = [
            "model": configuration.model,
            "temperature": temperature,
            "top_p": 0.85,
            "max_tokens": maxTokens,
            "enable_thinking": false,
            "chat_template_kwargs": [
                "enable_thinking": false
            ],
            "messages": SemanticFormatter.formattingMessages(
                transcript: text,
                mode: configuration.mode,
                outputLanguageDirective: configuration.outputLanguageDirective,
                useEmoji: configuration.useEmoji,
                customSystemPrompt: configuration.customSystemPrompt
            )
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SemanticFormatterError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw SemanticFormatterError.server(status: http.statusCode, message: message)
        }
        guard let chat = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let message = chat.choices.first?.message else {
            throw SemanticFormatterError.invalidResponse
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let usage = TokenUsage.parse(object["usage"]) {
            onUsage?(usage)
        }

        let raw = message.content ?? ""
        let cleaned = TranslationClient.sanitizeModelOutput(raw)
        let stripped = Self.stripLanguageMetaLines(Self.stripWrappingCodeFence(cleaned))
        guard !stripped.isEmpty else { throw SemanticFormatterError.emptyText }
        return stripped
    }

    /// Drop leaked prompt meta such as `[要求的输出语言：简体中文]`.
    static func stripLanguageMetaLines(_ text: String) -> String {
        let patterns = [
            #"^\s*\[?\s*要求的?输出语言\s*[:：].*$"#,
            #"^\s*\[?\s*输出语言\s*[:：].*$"#,
            #"^\s*\[?\s*REQUIRED\s+OUTPUT\s+LANGUAGE\s*[:：].*$"#,
            #"^\s*输出语言（最高优先级.*$"#,
            #"^\s*You MUST write the entire output in .*$"#,
        ]
        var lines = text.components(separatedBy: .newlines)
        lines.removeAll { line in
            patterns.contains { pattern in
                line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drop accidental ```markdown fences while keeping inner body.
    static func stripWrappingCodeFence(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.hasPrefix("```") else { return result }
        if let firstNewline = result.firstIndex(of: "\n") {
            result = String(result[result.index(after: firstNewline)...])
        } else {
            return result
        }
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Latest-only inference scheduler:
/// - only one job runs at a time
/// - new requests while busy replace any pending snapshot (discard intermediate)
/// - when the current job finishes, the latest pending job runs immediately
actor LatestOnlyScheduler {
    private var running = false
    private var pending: (@Sendable () async -> Void)?

    func enqueue(_ work: @escaping @Sendable () async -> Void) {
        if running {
            pending = work
            return
        }
        running = true
        Task {
            await work()
            await self.drain()
        }
    }

    private func drain() async {
        while let next = pending {
            pending = nil
            await next()
        }
        running = false
        // A submit may have raced after we cleared running; pick it up.
        if let late = pending {
            pending = nil
            running = true
            await late()
            await drain()
        }
    }
}
