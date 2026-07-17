import Foundation

// MARK: - Prompt IR

/// Intermediate representation between raw dictation and a target-specific final prompt.
/// Stage 1 (LLM) emits this JSON; Stage 2 (local Target Adapter) renders the paste-ready Prompt.
struct PromptIR: Codable, Equatable, Sendable {
    enum TaskType: String, Codable, CaseIterable, Sendable {
        case investigate
        case implement
        case explain
        case generate
        case refactor
        case review
        case other
    }

    enum ActionMode: String, Codable, CaseIterable, Sendable {
        case investigateOnly = "investigate_only"
        case modify
        case advise
        case generate
    }

    var taskType: TaskType
    var goal: String
    var context: [String]
    var currentState: [String]
    var requirements: [String]
    var constraints: [String]
    var uncertainties: [String]
    var focusAreas: [String]
    var expectedOutput: [String]
    var acceptanceCriteria: [String]
    var preserveVerbatim: [String]
    var actionMode: ActionMode

    enum CodingKeys: String, CodingKey {
        case taskType = "task_type"
        case goal
        case context
        case currentState = "current_state"
        case requirements
        case constraints
        case uncertainties
        case focusAreas = "focus_areas"
        case expectedOutput = "expected_output"
        case acceptanceCriteria = "acceptance_criteria"
        case preserveVerbatim = "preserve_verbatim"
        case actionMode = "action_mode"
    }

    init(
        taskType: TaskType,
        goal: String,
        context: [String] = [],
        currentState: [String] = [],
        requirements: [String] = [],
        constraints: [String] = [],
        uncertainties: [String] = [],
        focusAreas: [String] = [],
        expectedOutput: [String] = [],
        acceptanceCriteria: [String] = [],
        preserveVerbatim: [String] = [],
        actionMode: ActionMode
    ) {
        self.taskType = taskType
        self.goal = goal
        self.context = context
        self.currentState = currentState
        self.requirements = requirements
        self.constraints = constraints
        self.uncertainties = uncertainties
        self.focusAreas = focusAreas
        self.expectedOutput = expectedOutput
        self.acceptanceCriteria = acceptanceCriteria
        self.preserveVerbatim = preserveVerbatim
        self.actionMode = actionMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Local models often emit string-or-array and loose enum aliases.
        // decodeIfPresent(Enum.self) throws dataCorrupted on unknown raw values — use tolerant helpers.
        taskType = Self.decodeTaskType(c, forKey: .taskType)
        goal = Self.decodeString(c, forKey: .goal)
        context = Self.decodeStringList(c, forKey: .context)
        currentState = Self.decodeStringList(c, forKey: .currentState)
        requirements = Self.decodeStringList(c, forKey: .requirements)
        constraints = Self.decodeStringList(c, forKey: .constraints)
        uncertainties = Self.decodeStringList(c, forKey: .uncertainties)
        focusAreas = Self.decodeStringList(c, forKey: .focusAreas)
        expectedOutput = Self.decodeStringList(c, forKey: .expectedOutput)
        acceptanceCriteria = Self.decodeStringList(c, forKey: .acceptanceCriteria)
        preserveVerbatim = Self.decodeStringList(c, forKey: .preserveVerbatim)
        actionMode = Self.decodeActionMode(c, forKey: .actionMode)
    }

    private static func decodeString(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String {
        if let s = try? c.decode(String.self, forKey: key) {
            return s
        }
        if let list = try? c.decode([String].self, forKey: key) {
            return list.joined(separator: "；")
        }
        return ""
    }

    private static func decodeStringList(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [String] {
        if let list = try? c.decode([String].self, forKey: key) {
            return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let s = try? c.decode(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        // Rare: array of mixed JSON values coerced via lossless string conversion
        if var unkeyed = try? c.nestedUnkeyedContainer(forKey: key) {
            var items: [String] = []
            while !unkeyed.isAtEnd {
                if let s = try? unkeyed.decode(String.self) {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { items.append(t) }
                } else if let n = try? unkeyed.decode(Double.self) {
                    items.append(String(n))
                } else {
                    _ = try? unkeyed.decode(JSONValueSkip.self)
                }
            }
            return items
        }
        return []
    }

    private static func decodeTaskType(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> TaskType {
        guard let raw = try? c.decode(String.self, forKey: key) else { return .other }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .other }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "-", with: "_")
        if let exact = TaskType(rawValue: normalized) { return exact }
        switch normalized {
        case "debug", "diagnose", "analysis", "analyze", "investigate_only", "investigation":
            return .investigate
        case "fix", "bugfix", "code_fix", "change", "edit":
            return .implement
        case "description", "describe", "clarify":
            return .explain
        case "create", "write", "draft", "produce":
            return .generate
        case "cleanup", "restructure":
            return .refactor
        case "code_review", "pr_review", "audit":
            return .review
        default:
            return .other
        }
    }

    private static func decodeActionMode(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> ActionMode {
        guard let raw = try? c.decode(String.self, forKey: key) else { return .advise }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .advise }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "-", with: "_")
        if let exact = ActionMode(rawValue: normalized) { return exact }
        switch normalized {
        case "investigate", "analysis", "analyze", "readonly", "read_only", "diagnosis":
            return .investigateOnly
        case "implement", "edit", "change", "fix", "update":
            return .modify
        case "recommend", "suggestion", "suggest", "advice":
            return .advise
        case "create", "write", "draft", "produce":
            return .generate
        default:
            return .advise
        }
    }

    /// Discard unknown nested JSON tokens when coercing mixed arrays.
    private struct JSONValueSkip: Decodable {
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { return }
            if (try? container.decode(Bool.self)) != nil { return }
            if (try? container.decode(Double.self)) != nil { return }
            if (try? container.decode(String.self)) != nil { return }
            if (try? container.decode([JSONValueSkip].self)) != nil { return }
            if (try? container.decode([String: JSONValueSkip].self)) != nil { return }
        }
    }

    var isEmpty: Bool {
        goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && requirements.isEmpty
            && focusAreas.isEmpty
            && expectedOutput.isEmpty
    }

    static let schemaDescription = """
    Prompt IR JSON schema (emit exactly this object, no markdown, no commentary):
    {
      "task_type": "investigate|implement|explain|generate|refactor|review|other",
      "goal": "one-sentence true intent",
      "context": ["facts / background the user provided"],
      "current_state": ["existing implementation / known status / observed symptoms"],
      "requirements": ["explicit asks"],
      "constraints": ["limits, do-nots, scope guards"],
      "uncertainties": ["may / consider / tend / suspect — keep as uncertainty"],
      "focus_areas": ["what to inspect or emphasize"],
      "expected_output": ["deliverables"],
      "acceptance_criteria": ["how success is judged"],
      "preserve_verbatim": ["paths, symbols, params, quotes to keep exactly"],
      "action_mode": "investigate_only|modify|advise|generate"
    }
    Empty arrays are allowed. Keep each array concise (prefer ≤6 short items). Omit nothing that the user clearly stated.
    """
}

enum PromptCompilerError: LocalizedError {
    case invalidIR(String)
    case emptyIR

    var errorDescription: String? {
        switch self {
        case .invalidIR(let detail): "Prompt IR 无法解析：\(detail)"
        case .emptyIR: "Prompt IR 为空，无法编译。"
        }
    }
}

// MARK: - Target

enum PromptTargetKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case chat
    case codingCodex = "coding_codex"
    case codingClaude = "coding_claude"
    case codingGrok = "coding_grok"
    case research
    case image

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat: "通用 Chat"
        case .codingCodex: "Codex"
        case .codingClaude: "Claude Code"
        case .codingGrok: "Grok"
        case .research: "Deep Research"
        case .image: "图像生成"
        }
    }

    var caption: String {
        switch self {
        case .chat: "面向对话型 LLM 的自包含指令"
        case .codingCodex: "面向 Codex：读仓、改文件、跑命令/测试"
        case .codingClaude: "面向 Claude Code：仓库级编码代理"
        case .codingGrok: "面向 Grok 编码代理"
        case .research: "面向深度调研：证据、来源、对比"
        case .image: "面向文生图：主体、构图、风格、约束"
        }
    }

    var isCodingAgent: Bool {
        switch self {
        case .codingCodex, .codingClaude, .codingGrok: true
        default: false
        }
    }

    var profile: PromptTargetProfile {
        switch self {
        case .chat:
            return PromptTargetProfile(
                type: "chat",
                model: "chatgpt",
                capabilities: ["conversation", "reasoning", "writing"]
            )
        case .codingCodex:
            return PromptTargetProfile(
                type: "coding_agent",
                model: "codex",
                capabilities: ["read_repository", "edit_files", "run_commands", "run_tests"]
            )
        case .codingClaude:
            return PromptTargetProfile(
                type: "coding_agent",
                model: "claude_code",
                capabilities: ["read_repository", "edit_files", "run_commands", "run_tests", "use_tools"]
            )
        case .codingGrok:
            return PromptTargetProfile(
                type: "coding_agent",
                model: "grok",
                capabilities: ["read_repository", "edit_files", "run_commands", "run_tests"]
            )
        case .research:
            return PromptTargetProfile(
                type: "research",
                model: "deep_research",
                capabilities: ["web_search", "synthesize_sources", "compare"]
            )
        case .image:
            return PromptTargetProfile(
                type: "image",
                model: "image_generation",
                capabilities: ["text_to_image"]
            )
        }
    }
}

struct PromptTargetProfile: Sendable, Equatable {
    let type: String
    let model: String
    let capabilities: [String]

    var capabilitiesLine: String {
        capabilities.joined(separator: ", ")
    }
}

// MARK: - Stage 1: IR extraction (LLM) + Stage 2: Target Adapter (local)

enum PromptCompiler {
    struct FewShotExample: Sendable {
        let input: String
        let irJSON: String
    }

    /// Stage 1 system prompt: extract Prompt IR JSON only.
    static let irSystemPrompt = """
    You are Stage 1 of a Prompt Compiler: Intent → Prompt IR.

    Convert the user's natural language, speech transcript, fragmentary ideas, or incomplete instructions into ONE Prompt IR JSON object.

    Downstream Stage 2 (a local Target Adapter) will render this IR into the final Prompt. You do NOT write the final Prompt.

    Principles:
    1. Infer the real task intent; do not merely paraphrase into goal alone.
    2. Preserve explicit goals, context, tech names, parameters, paths, code symbols, constraints, prior conclusions, and preferences.
    3. Drop filler, repetition, ASR noise, and non-actionable chatter.
    4. If the user contradicts or corrects themselves, the last clear statement wins.
    5. Put scattered facts into the correct IR fields.
    6. NEVER invent facts, requirements, tech stacks, metrics, or decisions the user did not provide.
    7. Do not expand scope.
    8. Preserve uncertainty in "uncertainties" — never promote may/consider/tend/suspect into settled requirements.
    9. Make implicit-but-certain requirements explicit in requirements/focus_areas (e.g. “为什么慢” → bottlenecks, complexity, repeated work, blocking I/O, memory — without inventing SLOs).
    10. Choose action_mode carefully:
        - investigate_only: find cause / analyze, do not modify
        - modify: implement or change code/docs
        - advise: recommendations without necessarily editing
        - generate: produce content (prose, image prompt material, etc.)
    11. Do NOT answer the user's question. Do NOT execute the task.
    12. Output ONLY a single JSON object matching the schema. No markdown fences, no commentary, no prefix/suffix.

    \(PromptIR.schemaDescription)
    """

    // MARK: Few-shots (IR JSON) — keep compact; verbose examples inflate latency and truncate outputs.

    static let irFewShots: [FewShotExample] = [
        FewShotExample(
            input: "帮我看看为什么批量移动节点有时会回滚，节点越多越容易，先找原因不要改代码",
            irJSON: #"""
            {"task_type":"investigate","goal":"定位批量移动节点时偶发位置回滚的原因","context":["批量移动时偶发回滚","节点越多越容易出现"],"current_state":["移动后部分节点可能恢复到原位置"],"requirements":["先调查定位","基于本仓库实际实现给结论与证据"],"constraints":["不要直接改代码","不要只列通用猜测"],"uncertainties":[],"focus_areas":["乐观更新","批量位置请求","协同同步覆盖","并发/乱序"],"expected_output":["数据流","最可能根因","代码证据","修复方向"],"acceptance_criteria":["结论锚定本仓库路径"],"preserve_verbatim":[],"action_mode":"investigate_only"}
            """#
        ),
        FewShotExample(
            input: "那个登录页吧，不对，是设置页，把保存按钮改成主色，别动别的",
            irJSON: #"""
            {"task_type":"implement","goal":"将设置页保存按钮样式改为主色","context":["用户先提登录页后纠正为设置页"],"current_state":[],"requirements":["仅改设置页保存按钮主色相关样式"],"constraints":["不要改登录页","不要动其他按钮或无关样式"],"uncertainties":[],"focus_areas":["设置页保存按钮样式来源"],"expected_output":["最小必要改动"],"acceptance_criteria":["仅该按钮变主色"],"preserve_verbatim":["primary"],"action_mode":"modify"}
            """#
        ),
        FewShotExample(
            input: "帮我加个导出 CSV，可能还要支持筛选后的结果，你先看看现有导出怎么做的再改",
            irJSON: #"""
            {"task_type":"implement","goal":"增加 CSV 导出能力","context":[],"current_state":[],"requirements":["先读现有导出实现","在现有模式上最小扩展"],"constraints":["不要重构无关模块"],"uncertainties":["筛选结果是否一并支持需先核对现有实现"],"focus_areas":["现有导出实现","筛选与导出数据源"],"expected_output":["CSV 导出","改动与验证说明"],"acceptance_criteria":[],"preserve_verbatim":["CSV"],"action_mode":"modify"}
            """#
        ),
        FewShotExample(
            input: "嗯把这段话润色一下，语气专业一点，别太长，给客户邮件用：我们这周会把修改稿发给你们，有问题随时说",
            irJSON: #"""
            {"task_type":"generate","goal":"将原文润色为客户邮件可用的专业表述","context":["用途：客户邮件"],"current_state":[],"requirements":["专业简洁","保留原意","直接输出正文"],"constraints":["不编造未提供的承诺"],"uncertainties":[],"focus_areas":[],"expected_output":["润色后的邮件正文"],"acceptance_criteria":[],"preserve_verbatim":["我们这周会把修改稿发给你们，有问题随时说"],"action_mode":"generate"}
            """#
        ),
    ]

    // MARK: Stage 1 messages

    static func irSystemPrompt(languageDirective: String) -> String {
        """
        \(irSystemPrompt)

        Language for all IR string fields:
        \(languageDirective)
        """
    }

    static func irUserPrompt(sourceText: String) -> String {
        """
        Extract Prompt IR JSON from the following source. Output ONLY the JSON object.

        Source:
        \(sourceText)
        """
    }

    static func irExtractionMessages(
        sourceText: String,
        languageDirective: String
    ) -> [[String: String]] {
        var messages: [[String: String]] = [
            [
                "role": "system",
                "content": irSystemPrompt(languageDirective: languageDirective)
            ]
        ]

        for example in irFewShots {
            messages.append([
                "role": "user",
                "content": irUserPrompt(sourceText: example.input)
            ])
            messages.append([
                "role": "assistant",
                "content": example.irJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }

        messages.append([
            "role": "user",
            "content": irUserPrompt(sourceText: sourceText)
        ])
        messages.append([
            "role": "assistant",
            "content": "<think>\n</think>\n"
        ])

        return messages
    }

    // MARK: Parse IR

    static func parseIR(from raw: String) throws -> PromptIR {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PromptCompilerError.emptyIR }

        let candidates = jsonCandidates(from: trimmed)
        let decoder = JSONDecoder()
        var lastError: Error?
        var sawObject = false

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if candidate.contains("{") { sawObject = true }
            do {
                let ir = try decoder.decode(PromptIR.self, from: data)
                if ir.isEmpty { throw PromptCompilerError.emptyIR }
                return ir
            } catch let error as PromptCompilerError {
                throw error
            } catch {
                lastError = error
            }
        }

        let snippet = trimmed
            .replacingOccurrences(of: "\n", with: " ")
        let preview = snippet.count > 160 ? String(snippet.prefix(160)) + "…" : snippet
        let reason: String
        if !sawObject {
            reason = "模型未返回 JSON 对象"
        } else if let lastError {
            reason = compactDecodingError(lastError)
        } else {
            reason = "未找到可解析的 JSON 对象"
        }
        throw PromptCompilerError.invalidIR("\(reason)｜片段：\(preview)")
    }

    /// Short human-readable DecodingError without dumping the full Swift dump.
    static func compactDecodingError(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return String(describing: error)
        }
        switch decoding {
        case .dataCorrupted(let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            let where_ = path.isEmpty ? "root" : path
            return "字段 \(where_) 数据损坏：\(ctx.debugDescription)"
        case .keyNotFound(let key, let ctx):
            let path = (ctx.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            return "缺少字段 \(path)"
        case .typeMismatch(let type, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            let where_ = path.isEmpty ? "root" : path
            return "字段 \(where_) 类型不匹配（期望 \(type)）"
        case .valueNotFound(let type, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            let where_ = path.isEmpty ? "root" : path
            return "字段 \(where_) 值为空（期望 \(type)）"
        @unknown default:
            return String(describing: error)
        }
    }

    /// Prefer fenced JSON, then outermost `{...}` slices.
    static func jsonCandidates(from text: String) -> [String] {
        var results: [String] = []
        let unfenced = stripOuterCodeFence(text)
        if unfenced != text {
            results.append(unfenced)
        }

        if let sliced = extractJSONObject(from: unfenced) {
            results.append(sliced)
        }
        results.append(unfenced)
        results.append(text)

        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }
    }

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

    static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var end: String.Index?

        for index in text[start...].indices {
            let ch = text[index]
            if inString {
                if escape {
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }
            switch ch {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            default:
                break
            }
            if end != nil { break }
        }

        guard let end else { return nil }
        return String(text[start...end])
    }

    // MARK: Stage 2 — Target Adapter (local)

    static func render(ir: PromptIR, target: PromptTargetKind) -> String {
        switch target {
        case .codingCodex, .codingClaude, .codingGrok:
            return PromptTargetAdapter.renderCoding(ir: ir, target: target)
        case .chat:
            return PromptTargetAdapter.renderChat(ir: ir)
        case .research:
            return PromptTargetAdapter.renderResearch(ir: ir)
        case .image:
            return PromptTargetAdapter.renderImage(ir: ir)
        }
    }

    /// Full two-stage compile from raw model IR text.
    static func compile(irRaw: String, target: PromptTargetKind) throws -> String {
        let ir = try parseIR(from: irRaw)
        let rendered = render(ir: ir, target: target)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rendered.isEmpty else { throw PromptCompilerError.emptyIR }
        return rendered
    }

    static func requestEnvelope(sourceText: String, target: PromptTargetKind) -> [String: Any] {
        let profile = target.profile
        return [
            "mode": "prompt_optimizer",
            "pipeline": ["intent_understanding", "prompt_ir", "target_adapter", "final_prompt"],
            "target": [
                "type": profile.type,
                "model": profile.model,
                "capabilities": profile.capabilities
            ],
            "input": sourceText
        ]
    }
}

// MARK: - Local adapters

enum PromptTargetAdapter {
    static func renderCoding(ir: PromptIR, target: PromptTargetKind) -> String {
        let agentName: String = {
            switch target {
            case .codingClaude: return "Claude Code"
            case .codingGrok: return "Grok"
            default: return "Codex"
            }
        }()

        var sections: [String] = []

        switch ir.actionMode {
        case .investigateOnly:
            sections.append(leadInvestigate(goal: ir.goal))
        case .modify:
            sections.append(leadModify(goal: ir.goal))
        case .advise:
            sections.append("请基于当前项目给出可执行建议：\(ir.goal)")
        case .generate:
            sections.append("请完成以下生成任务：\(ir.goal)")
        }

        appendSection(&sections, title: "背景与上下文", items: ir.context)
        appendSection(&sections, title: "已知现象 / 当前状态", items: ir.currentState)

        if !ir.focusAreas.isEmpty {
            sections.append("请先阅读并理解相关实现，重点检查：")
            sections.append(numbered(ir.focusAreas))
        }

        var requirements = ir.requirements
        var constraints = ir.constraints

        switch ir.actionMode {
        case .investigateOnly:
            constraints.append(contentsOf: [
                "先调查并定位问题，不要直接修改代码。",
                "必须基于当前项目实际实现给出结论，不要只列举通用可能原因。",
                "给出关键代码路径和数据流，并提供能支持结论的证据。"
            ])
        case .modify:
            requirements.append(contentsOf: [
                "先理解现有实现与上下文，再做最小必要修改。",
                "保持与当前任务无关的功能和行为不变。"
            ])
            constraints.append("不要修改与当前任务无关的部分。")
        case .advise, .generate:
            break
        }

        // De-dupe while preserving order
        requirements = unique(requirements)
        constraints = unique(constraints)

        appendSection(&sections, title: "具体要求", items: requirements)
        appendSection(&sections, title: "约束条件", items: constraints)
        appendUncertainty(&sections, items: ir.uncertainties)
        appendSection(&sections, title: "预期输出", items: ir.expectedOutput)
        appendSection(&sections, title: "验收标准", items: ir.acceptanceCriteria)

        if !ir.preserveVerbatim.isEmpty {
            sections.append("请原样保留这些标识符/路径/符号：\(ir.preserveVerbatim.joined(separator: "、"))")
        }

        // Light target hint — dense, not roleplay
        sections.append("目标代理：\(agentName)（可读写仓库、运行命令与测试）。")

        return sections.joined(separator: "\n\n")
    }

    static func renderChat(ir: PromptIR) -> String {
        var sections: [String] = []
        if !ir.goal.isEmpty {
            sections.append(ir.goal.hasPrefix("请") ? ir.goal : "请\(ir.goal)")
        }
        appendSection(&sections, title: "背景", items: ir.context)
        appendSection(&sections, title: "要求", items: unique(ir.requirements + ir.focusAreas))
        appendSection(&sections, title: "约束", items: ir.constraints)
        appendUncertainty(&sections, items: ir.uncertainties)
        appendSection(&sections, title: "输出", items: ir.expectedOutput)

        if let source = ir.preserveVerbatim.first, ir.actionMode == .generate {
            sections.append("原文：\n\(source)")
        } else if !ir.preserveVerbatim.isEmpty {
            sections.append("请保留：\(ir.preserveVerbatim.joined(separator: "、"))")
        }

        return compact(sections)
    }

    static func renderResearch(ir: PromptIR) -> String {
        var sections: [String] = []
        sections.append(ir.goal.hasPrefix("请") ? ir.goal : "请调研：\(ir.goal)")
        appendSection(&sections, title: "背景", items: ir.context)
        appendSection(&sections, title: "重点关注", items: ir.focusAreas)
        appendSection(&sections, title: "要求", items: ir.requirements)
        appendSection(&sections, title: "约束", items: ir.constraints)
        appendUncertainty(&sections, items: ir.uncertainties)
        var outputs = ir.expectedOutput
        if !outputs.contains(where: { $0.contains("来源") || $0.lowercased().contains("source") }) {
            outputs.append("标注关键来源或依据")
        }
        appendSection(&sections, title: "交付", items: outputs)
        appendSection(&sections, title: "验收", items: ir.acceptanceCriteria)
        return sections.joined(separator: "\n\n")
    }

    static func renderImage(ir: PromptIR) -> String {
        var parts: [String] = []
        if !ir.goal.isEmpty { parts.append(ir.goal) }
        parts.append(contentsOf: ir.requirements)
        parts.append(contentsOf: ir.focusAreas)
        parts.append(contentsOf: ir.context)
        let negatives = ir.constraints.map { constraint in
            constraint.hasPrefix("不要") || constraint.lowercased().hasPrefix("no ")
                ? constraint
                : "no \(constraint)"
        }
        parts.append(contentsOf: negatives)
        // Prefer a single dense line for image models when short; else bullet-like commas.
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return joined.joined(separator: ", ")
    }

    // MARK: Helpers

    private static func leadInvestigate(goal: String) -> String {
        if goal.hasPrefix("请") { return goal }
        if goal.contains("定位") || goal.contains("调查") || goal.contains("分析") {
            return "请\(goal)"
        }
        return "请调查并定位：\(goal)"
    }

    private static func leadModify(goal: String) -> String {
        if goal.hasPrefix("请") { return goal }
        return "请修改/实现：\(goal)"
    }

    private static func appendSection(_ sections: inout [String], title: String, items: [String]) {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        if cleaned.count == 1, title == "任务目标" {
            sections.append("\(title)：\n\(cleaned[0])")
            return
        }
        sections.append("\(title)：\n\(bullets(cleaned))")
    }

    private static func appendUncertainty(_ sections: inout [String], items: [String]) {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        let framed = cleaned.map { item -> String in
            if item.contains("可能") || item.lowercased().contains("may") || item.contains("尚未") {
                return item
            }
            return "可能：\(item)"
        }
        sections.append("不确定性（保持为未决，勿当作已确认需求）：\n\(bullets(framed))")
    }

    private static func bullets(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func numbered(_ items: [String]) -> String {
        items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private static func compact(_ sections: [String]) -> String {
        sections.joined(separator: "\n\n")
    }
}
