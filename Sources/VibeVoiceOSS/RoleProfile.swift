import Foundation

/// A reusable professional context that helps the language model interpret dictation.
struct RoleProfile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var symbol: String
    var background: String
    var terminology: String
    var styleGuide: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        symbol: String = "person.fill",
        background: String,
        terminology: String = "",
        styleGuide: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.background = background
        self.terminology = terminology
        self.styleGuide = styleGuide
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !background.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Added below the user's explicit custom prompt. It provides context, never new facts.
    var contextPrompt: String {
        """
        当前专业角色背景（低于用户自定义 Prompt 的优先级）：
        角色：\(name)
        工作背景：\(background)
        专业词汇与常见语音误辨修正：\(terminology.isEmpty ? "无额外词表。" : terminology)
        表达与边界：\(styleGuide.isEmpty ? "保持原意，不补造事实或承诺。" : styleGuide)

        只可依据原始转写纠正明显的同音、断词或术语错误；不得凭专业常识虚构名称、数字、版本、价格、交期、承诺或结论。保留原文中的不确定性、条件和待确认事项。
        """
    }

    static let softwareEngineer = RoleProfile(
        id: "preset-software-engineer",
        name: "程式工程师",
        symbol: "chevron.left.forwardslash.chevron.right",
        background: "软件开发、代码评审、缺陷排查、技术方案、研发协作与工程文档。",
        terminology: "识别并保留编程语言、框架、库、API、SDK、CLI 命令、路径、文件名、错误码、版本号、变量名、函数名、数据库字段、Git 分支和英文技术缩写。可将明显的同音误识别纠正为上下文已支持的技术术语。",
        styleGuide: "使用准确、简洁的工程表达。代码、命令、路径和 identifier 保持原样；不要虚构 API、参数、版本、性能结论、故障原因或修复结果。对推测使用“可能”“待确认”“需复现”等措辞。"
    )

    static let foreignTrade = RoleProfile(
        id: "preset-foreign-trade",
        name: "外贸人员",
        symbol: "shippingbox.fill",
        background: "国际贸易客户沟通、询盘跟进、报价、商务谈判、订单协调与跨境物流。",
        terminology: "识别并保留 RFQ、quotation、PI、PO、MOQ、FOB、CIF、EXW、DDP、L/C、T/T、lead time、sample、HS code、packing list、B/L、container、freight、unit price、规格、包装、币种、数量、港口与交期。",
        styleGuide: "输出应礼貌、清晰、专业，适用于客户沟通和商务谈判。清楚区分已确认、可协商和待确认事项；不得擅自承诺价格、折扣、付款条件、库存、交期、运费、认证或赔偿。保留条件、数字、币种、数量、Incoterms 和“待确认／以最终报价为准”等限制。"
    )

    static let defaultProfiles = [softwareEngineer, foreignTrade]
}

struct RoleResolution: Equatable, Sendable {
    let roleID: String
    let reason: String
}

enum RoleResolutionError: LocalizedError {
    case invalidResponse

    var errorDescription: String? { "角色判定模型返回了无效结果。" }
}

struct RoleResolver: Sendable {
    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    static func messages(text: String, candidates: [RoleProfile]) -> [[String: String]] {
        let cards = candidates.map { profile in
            "ID: \(profile.id)\n名称: \(profile.name)\n背景: \(profile.background)\n词汇: \(profile.terminology)"
        }.joined(separator: "\n\n---\n\n")
        return [
            ["role": "system", "content": """
            你是语音输入的角色判定器。只从候选角色中选择最符合本次内容工作语境的一项。
            不要推断用户身份，不要创建新角色，也不要改写原文。
            只输出 JSON，不要 markdown：{\"role_id\":\"候选 ID\",\"reason\":\"不超过 24 字的判断依据\"}
            候选角色：
            \(cards)
            """],
            ["role": "user", "content": text]
        ]
    }

    static func parse(_ raw: String, candidates: [RoleProfile]) throws -> RoleResolution {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            body = String(trimmed[start...end])
        } else {
            body = trimmed
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roleID = json["role_id"] as? String,
              candidates.contains(where: { $0.id == roleID }) else {
            throw RoleResolutionError.invalidResponse
        }
        return RoleResolution(roleID: roleID, reason: (json["reason"] as? String) ?? "")
    }

    func resolve(
        text: String,
        candidates: [RoleProfile],
        endpoint: String,
        model: String,
        apiKey: String
    ) async throws -> RoleResolution {
        guard let url = URL(string: endpoint) else { throw TranslationError.invalidEndpoint }
        guard EndpointSecurity.allowsCredentialTransmission(to: url, apiKey: apiKey) else {
            throw TranslationError.insecureEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        TranslationClient.applyBearerIfNeeded(apiKey, to: &request)
        let payload = TranslationClient.chatCompletionPayload(
            model: TranslationClient.sanitizeModelName(model),
            messages: Self.messages(text: text, candidates: candidates),
            temperature: 0,
            topP: 1,
            maxTokens: 128,
            endpoint: endpoint
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RoleResolutionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.server(
                status: http.statusCode,
                message: TranslationClient.authHintIfNeeded(
                    status: http.statusCode, host: url.host,
                    body: String(data: data, encoding: .utf8) ?? "未知错误",
                    model: model, endpoint: endpoint
                )
            )
        }
        guard let chat = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = chat.choices.first?.message.content else {
            throw RoleResolutionError.invalidResponse
        }
        return try Self.parse(content, candidates: candidates)
    }
}
