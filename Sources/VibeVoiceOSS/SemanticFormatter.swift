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
    case insecureEndpoint

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "结构化整理接口地址无效。"
        case let .server(status, message): "整理模型返回 HTTP \(status)：\(message)"
        case .invalidResponse: "整理模型返回了无法解析的响应。"
        case .emptyText: "整理完成，但返回文本为空。"
        case let .timedOut(seconds):
            "结构化整理超过 \(seconds) 秒，已自动中断。请检查百炼模型限流、上下文长度或缩短输入后重试。"
        case .insecureEndpoint:
            "为保护 API Key，远程明文 HTTP 接口不可用；请改用 HTTPS，或仅在本机回环地址使用 HTTP。"
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

    /// Insert a newline after sentence terminators so the next sentence starts on a new line.
    /// Used for live HUD captions, LLM input preparation, and final-output fallback.
    static func insertSentenceLineBreaks(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var out = String()
        out.reserveCapacity(text.count + 8)
        let chars = Array(text)
        let cjkTerminators: Set<Character> = ["。", "！", "？", "；"]
        let latinTerminators: Set<Character> = [".", "!", "?"]
        let trailingClosers: Set<Character> = ["\"", "'", "”", "’", "）", ")", "」", "』", "》", "›", "»"]

        var i = 0
        while i < chars.count {
            let ch = chars[i]
            out.append(ch)

            let isTerminator: Bool
            if cjkTerminators.contains(ch) {
                isTerminator = true
            } else if latinTerminators.contains(ch) {
                // Keep decimals like 3.14 on one line.
                let prevIsDigit = i > 0 && chars[i - 1].isNumber
                let nextIsDigit = i + 1 < chars.count && chars[i + 1].isNumber
                isTerminator = !(ch == "." && prevIsDigit && nextIsDigit)
            } else {
                isTerminator = false
            }

            guard isTerminator else {
                i += 1
                continue
            }

            var j = i + 1
            while j < chars.count, trailingClosers.contains(chars[j]) {
                out.append(chars[j])
                j += 1
            }
            // Collapse a single space after Latin ". " into the line break.
            if j < chars.count, chars[j] == " " || chars[j] == "\u{00A0}" {
                j += 1
            }
            if j < chars.count, chars[j] != "\n" {
                out.append("\n")
            }
            i = j
        }
        return out
    }

    /// When the model collapses multi-sentence text into one line, restore readable breaks.
    /// If the model already produced newlines, keep its layout.
    static func ensureParagraphOutput(_ text: String, mode: StructureMode) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.contains(where: \.isNewline) {
            return trimmed
        }

        let broken = insertSentenceLineBreaks(trimmed)
        guard broken.contains(where: \.isNewline) else { return trimmed }

        switch mode {
        case .clean:
            // Light cleanup: one sentence per line, no extra blank lines.
            return broken
        case .ultraConcise, .structured, .rewrite:
            // Paragraph feel for longer multi-sentence paste targets.
            let lines = broken.split(whereSeparator: \.isNewline).map(String.init)
            if lines.count >= 2, trimmed.count >= 40 || lines.count >= 3 {
                return lines.joined(separator: "\n\n")
            }
            return broken
        }
    }

    /// Shared chat-reading layout with decorative emoji (when enabled).
    private static let chatLayoutRulesWithEmoji = """
    对话阅读排版（内容整理 / 超精简 / 深度整理均必须遵守，最终粘贴文本也必须带换行）：
    - 禁止把多句内容挤成没有换行的一整段。
    - 短段 + 空行：避免大段堆砌；一句一事更易扫读。
    - 长文分段：正文超过约 40 字或含 2 句以上时，必须用换行拆开；每一句单独成行，语义相关的短句之间用空行分段。
    - 清单仍用 - 或编号，每条一行。
    - 不要为凑行宽硬拆专有名词、路径、代码标识符或英文专名。
    - 必须使用修饰性 emoji：每个分区标题或关键要点行前加 1 个 macOS / 聊天输入法常规 Unicode emoji（如 ✅ 📌 💡 ⚠️ 📝 🎯 ✨ 🚀 🔍 💬）。
    - 纯文字、毫无 emoji 的输出视为不合格；至少出现 1–3 个 emoji，让读起来更轻松有趣。
    - 不要用 [NOTE]、[TODO]、[OK] 这类方括号单词标签代替 emoji。
    - 不要整行刷 emoji，也不要在每个清单条目前都塞 emoji。
    """

    /// Same layout without decorative emoji (default).
    private static let chatLayoutRulesPlain = """
    对话阅读排版（内容整理 / 超精简 / 深度整理均必须遵守，最终粘贴文本也必须带换行）：
    - 禁止把多句内容挤成没有换行的一整段。
    - 短段 + 空行：避免大段堆砌；一句一事更易扫读。
    - 长文分段：正文超过约 40 字或含 2 句以上时，必须用换行拆开；每一句单独成行，语义相关的短句之间用空行分段。
    - 清单仍用 - 或编号，每条一行。
    - 不要为凑行宽硬拆专有名词、路径、代码标识符或英文专名。
    - 可用简短中文小标题（如「结论」「待办」「问题」），不要使用 emoji。
    - 不要用 [NOTE]、[TODO]、[OK] 这类方括号单词标签。
    - 不要为装饰而堆砌符号。
    """

    private static func chatLayoutRules(useEmoji: Bool) -> String {
        useEmoji ? chatLayoutRulesWithEmoji : chatLayoutRulesPlain
    }

    /// Light-cleanup few-shots: one sentence per line, no titles/lists.
    static let layoutFewShotsClean: [FewShotExample] = [
        FewShotExample(
            input: "嗯那个明天下午三点跟产品开个会吧，主要聊一下首页改版，还有就是埋点可能要补一下，另外设计稿我可能周五才能给到你们，你们先看看现有的交互。",
            output: """
            明天下午三点跟产品开个会。
            主要聊一下首页改版。
            埋点可能要补一下。
            设计稿我可能周五才能给到你们。
            你们先看看现有的交互。
            """
        ),
        FewShotExample(
            input: "今天把登录超时修了，然后导出 CSV 还没做，哦对了文档也要更新一下，接口那块小王说可能下周才有空。",
            output: """
            今天把登录超时修了。
            导出 CSV 还没做。
            文档也要更新一下。
            接口那块小王说可能下周才有空。
            """
        ),
        FewShotExample(
            input: "我觉得这个页面加载有点慢，用户一进来就转圈，可能是接口慢也可能是前端渲染问题，你帮我看看吧。",
            output: """
            这个页面加载有点慢。
            用户一进来就转圈。
            可能是接口慢，也可能是前端渲染问题。
            你帮我看看吧。
            """
        ),
    ]

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
            return layoutFewShotsClean
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

        口述修正规则（必须遵守）：
        - 把整段口述视为会不断修订的草稿；后面明确出现的「算了、还是、改成、应该是、不是…而是…」会覆盖前面相冲突的计划或对象。
        - 输出只保留最终确认的意图，不罗列被否决的时间、地点、对象或中间犹豫；与最终意图无关的自言自语也应删除。
        - 例如「下午三点看比赛，算了四点，还是改明天上午，应该是看电影」应整理为「我打算明天上午去看电影。」
        - 只有当最后表达仍不确定时，才保留「可能、待确认」等不确定性，不得擅自补全缺失信息。

        安全边界（必须遵守）：
        - 必须区分事实、决定、建议、倾向和不确定判断。
        - 不能把「可能、考虑、倾向、建议」改写成已经确定的结论。
        - 模型可以整理表达，但不能替用户改变决策。
        - 准确保留原意，不增加使用者没有表达的信息。
        - 不要解释你做了哪些修改。
        - 只输出整理完成的正文。
        - 使用 Markdown，但不要输出 Markdown 代码块。
        - 最终输出必须是可直接粘贴的多行正文；禁止把多句挤成一整段无换行文本。
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
            排版（必须遵守，最终粘贴文本也必须带换行）：
            - 多句内容必须一句一行；句号 / 问号 / 感叹号结束后换行，下一句从新行开始。
            - 超过约 40 字或含 2 句以上时，禁止输出没有换行的一整段。
            - 单句短文本可保持一行。
            - 输入若已按句号预分段，必须保留这些换行，只在各行内做轻度修正。

            只做：
            - 标点与断句修正；每一句末尾补全句号、问号或感叹号；
            - 修复语音识别造成的明显错词；
            - 删除无实际意义的口头语（嗯、啊、就是、然后、那个、我觉得吧等），删完后仍保持一句一行；
            - 合并明显重复或自我修正的表述，以最后确认的意思为准。

            不要调整论述顺序，不要加标题，不要改成清单或步骤，不要大幅改写措辞，不要插入空行制造段落标题感。
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
            - 每个要点单独成行；要点之间用空行分段；
            - 不确定处保留为「可能 / 待确认」，勿升格为定论。

            \(layoutClose)
            """
        case .structured:
            let formHints: String
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

                请严格对照样例：有分区就要有修饰性 emoji；段落之间必须空行；不要输出干巴巴的一整段纯文字。
                """
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

                请严格对照样例：短段换行、主题之间空行分段；可用中文小标题；不要使用 emoji；不要输出一整段无换行正文。
                """
            }
            return """
            \(shared)
            \(languageBlock)

            \(chatLayoutRules(useEmoji: useEmoji))

            当前强度：内容整理（structured）
            在轻度整理基础上，额外允许：
            - 理解段落与信息关系，并按语义重组为可读段落；
            - 根据语义关系调整表达顺序，但不得改变原有结论；
            - 使用标题、项目符号或编号步骤（仅在内容确实需要时）；
            - 提取明确的结论与待办（仅当原文已经表达这些内容时）；
            - 长文必须段落化：相关句子组成段，段与段之间空行。

            \(formHints)
            """
        case .rewrite:
            let layoutClose = useEmoji
                ? "排版仍按对话阅读习惯与样例：正式短段、空行分段，且必须带修饰性 emoji。"
                : "排版仍按对话阅读习惯与样例：正式短段、空行分段；不要使用 emoji。"
            return """
            \(shared)
            \(languageBlock)

            \(chatLayoutRules(useEmoji: useEmoji))

            当前强度：深度整理（rewrite）
            在内容整理基础上，额外允许：
            - 更明显地改写措辞，使其更正式、紧凑；
            - 压缩冗余；
            - 重构文章组织为清晰段落；
            - 转换为适合邮件、报告或方案文档的表达；
            - 长文必须分段输出：每个段落表达一个完整意思，段与段之间空行。

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
        // Pre-segment by sentence so the model sees the intended line structure
        // (ASR transcripts are usually one continuous line).
        let prepared = insertSentenceLineBreaks(
            transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var body = """
        原始语音转写如下（已按句末标点预分段；请在整理时保留并强化换行，最终输出禁止合并成一整段）：

        \(prepared)
        """

        guard let mode else { return body }

        switch mode {
        case .clean:
            body += """


            请按「轻度整理」输出：修正标点与口头语；多句必须一句一行；超过约 40 字或含 2 句以上时禁止无换行整段；不要加标题或清单。
            """
        case .ultraConcise:
            if useEmoji {
                body += """


                请按「超精简」输出：只保留关键要点；每个要点单独成行；要点之间空行；分区标题带常规修饰性 emoji；不要纯文字干巴一整段。
                """
            } else {
                body += """


                请按「超精简」输出：只保留关键要点；每个要点单独成行；要点之间空行；不要使用 emoji；不要纯文字干巴一整段。
                """
            }
        case .structured:
            if useEmoji {
                body += """


                请按「内容整理」输出：按语义重组为短段 / 清单 / 步骤；多句必须换行；主题之间空行分段；分区标题带常规修饰性 emoji；不要纯文字干巴一整段。
                """
            } else {
                body += """


                请按「内容整理」输出：按语义重组为短段 / 清单 / 步骤；多句必须换行；主题之间空行分段；可用中文小标题；不要使用 emoji；不要纯文字干巴一整段。
                """
            }
        case .rewrite:
            if useEmoji {
                body += """


                请按「深度整理」输出：改写成正式短段；长文必须段落化；段与段之间空行；分区标题带常规修饰性 emoji；不要纯文字干巴一整段。
                """
            } else {
                body += """


                请按「深度整理」输出：改写成正式短段；长文必须段落化；段与段之间空行；不要使用 emoji；不要纯文字干巴一整段。
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
        guard EndpointSecurity.allowsCredentialTransmission(
            to: url, apiKey: configuration.apiKey
        ) else {
            throw SemanticFormatterError.insecureEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(Self.requestTimeoutSeconds)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        TranslationClient.applyBearerIfNeeded(configuration.apiKey, to: &request)

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

        let payload = TranslationClient.chatCompletionPayload(
            model: configuration.model,
            messages: SemanticFormatter.formattingMessages(
                transcript: text,
                mode: configuration.mode,
                outputLanguageDirective: configuration.outputLanguageDirective,
                useEmoji: configuration.useEmoji,
                customSystemPrompt: configuration.customSystemPrompt
            ),
            temperature: temperature,
            topP: 0.85,
            maxTokens: maxTokens,
            endpoint: configuration.endpoint
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SemanticFormatterError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = HTTPErrorBody.summarize(data)
            throw SemanticFormatterError.server(
                status: http.statusCode,
                message: TranslationClient.authHintIfNeeded(
                    status: http.statusCode,
                    host: url.host,
                    body: message,
                    model: configuration.model,
                    endpoint: configuration.endpoint
                )
            )
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
        // Models often ignore layout instructions and return one long line; restore breaks.
        return SemanticFormatter.ensureParagraphOutput(stripped, mode: configuration.mode)
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
