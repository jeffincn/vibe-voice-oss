import XCTest
@testable import VibeVoiceOSS

final class SemanticFormatterTests: XCTestCase {
    func testAutoModeShortTextUsesClean() {
        let mode = SemanticFormatter.resolveMode(for: "明天开会", intensity: .auto)
        XCTAssertEqual(mode, .clean)
    }

    func testAutoModeLongTextUsesStructured() {
        let text = String(repeating: "这是一段需要整理的技术方案说明内容。", count: 6)
        XCTAssertGreaterThan(text.count, 100)
        let mode = SemanticFormatter.resolveMode(for: text, intensity: .auto)
        XCTAssertEqual(mode, .structured)
    }

    func testAutoModeMidRangeWithListCuesUsesStructured() {
        let text = "首先把接口改掉，其次再修延迟，另外还有待办要确认。"
        let mode = SemanticFormatter.resolveMode(for: text, intensity: .auto)
        XCTAssertEqual(mode, .structured)
    }

    func testManualRewriteNeverOverriddenByLength() {
        let mode = SemanticFormatter.resolveMode(for: "短", intensity: .rewrite)
        XCTAssertEqual(mode, .rewrite)
    }

    func testManualUltraConciseResolvesDirectly() {
        let mode = SemanticFormatter.resolveMode(for: String(repeating: "长", count: 200), intensity: .ultraConcise)
        XCTAssertEqual(mode, .ultraConcise)
    }

    func testUltraConciseAppearsInIntensityPicker() {
        XCTAssertTrue(StructureIntensity.allCases.contains(.ultraConcise))
        XCTAssertEqual(StructureIntensity.ultraConcise.label, "超精简")
        XCTAssertTrue(StructureIntensity.ultraConcise.caption.contains("压缩")
            || StructureIntensity.ultraConcise.caption.contains("要点"))
    }

    func testCleanPromptForbidsTitles() {
        let prompt = SemanticFormatter.systemPrompt(for: .clean)
        XCTAssertTrue(prompt.contains("轻度整理"))
        XCTAssertTrue(prompt.contains("不要加标题"))
        XCTAssertTrue(prompt.contains("不能把「可能、考虑、倾向、建议」改写成已经确定的结论"))
        XCTAssertTrue(prompt.contains("与原始转写保持同一语言"))
    }

    func testCleanPromptHonorsOutputLanguageDirective() {
        let prompt = SemanticFormatter.systemPrompt(
            for: .clean,
            outputLanguageDirective: "You MUST write the entire output in Simplified Chinese."
        )
        XCTAssertTrue(prompt.contains("Simplified Chinese"))
        XCTAssertTrue(prompt.contains("输出语言（最高优先级"))
    }

    func testStructuredPromptAllowsSemanticLayout() {
        let prompt = SemanticFormatter.systemPrompt(for: .structured, useEmoji: true)
        XCTAssertTrue(prompt.contains("内容整理"))
        XCTAssertTrue(prompt.contains("编号步骤"))
        XCTAssertTrue(prompt.contains("不要机械地为所有内容增加"))
        XCTAssertTrue(prompt.contains("对话阅读排版") || prompt.contains("短段"))
        XCTAssertTrue(prompt.contains("必须使用修饰性 emoji") || prompt.contains("不合格"))
        XCTAssertTrue(prompt.contains("Unicode emoji") || prompt.contains("✅") || prompt.contains("📌"))
    }

    func testStructuredPromptWithoutEmojiOmitsEmojiRequirement() {
        let prompt = SemanticFormatter.systemPrompt(for: .structured, useEmoji: false)
        XCTAssertTrue(prompt.contains("内容整理"))
        XCTAssertTrue(prompt.contains("不要使用 emoji"))
        XCTAssertFalse(prompt.contains("必须使用修饰性 emoji"))
    }

    func testUltraConciseIsStricterRuleNotSeparateLayoutSystem() {
        let prompt = SemanticFormatter.systemPrompt(for: .ultraConcise, useEmoji: true)
        XCTAssertTrue(prompt.contains("超精简"))
        XCTAssertTrue(prompt.contains("更严") || prompt.contains("更狠") || prompt.contains("归纳"))
        XCTAssertTrue(prompt.contains("对话阅读排版") || prompt.contains("同一套排版"))
        XCTAssertTrue(prompt.contains("不是另一套排版系统"))
        XCTAssertTrue(prompt.contains("修饰性 emoji") || prompt.contains("必须带"))
    }

    func testLayoutFewShotsTeachShortBlocksAndRealEmoji() {
        let structured = SemanticFormatter.layoutFewShotsStructuredEmoji
        XCTAssertFalse(structured.isEmpty)
        XCTAssertTrue(structured.allSatisfy { $0.output.contains("✅") || $0.output.contains("📌") || $0.output.contains("🔍") })
        XCTAssertTrue(structured.contains(where: { $0.output.contains("\n\n") }))

        let plain = SemanticFormatter.layoutFewShotsStructuredPlain
        XCTAssertEqual(plain.count, structured.count)
        XCTAssertTrue(plain.allSatisfy { !$0.output.contains("📌") && !$0.output.contains("✅") })

        let ultra = SemanticFormatter.layoutFewShotsUltraEmoji
        XCTAssertEqual(ultra.count, structured.count)
        // Ultra examples should be shorter than structured for the same inputs.
        for (s, u) in zip(structured, ultra) {
            XCTAssertEqual(s.input, u.input)
            XCTAssertLessThan(u.output.count, s.output.count)
        }
    }

    func testStructuredUserPromptRequiresEmoji() {
        let prompt = SemanticFormatter.userPrompt(transcript: "测试", mode: .structured, useEmoji: true)
        XCTAssertTrue(prompt.contains("emoji"))
        let plain = SemanticFormatter.userPrompt(transcript: "测试", mode: .structured, useEmoji: false)
        XCTAssertTrue(plain.contains("不要使用 emoji"))
        let clean = SemanticFormatter.userPrompt(transcript: "测试", mode: .clean)
        XCTAssertFalse(clean.contains("emoji"))
    }

    func testFormattingMessagesIncludeFewShotsForStructured() {
        let messages = SemanticFormatter.formattingMessages(
            transcript: "随便说一句",
            mode: .structured,
            useEmoji: true
        )
        XCTAssertEqual(messages.first?["role"], "system")
        let assistantBodies = messages.filter { $0["role"] == "assistant" && $0["content"]?.contains("📌") == true }
        XCTAssertFalse(assistantBodies.isEmpty)
        XCTAssertTrue(messages.contains(where: { $0["role"] == "user" && $0["content"]?.contains("随便说一句") == true }))
    }

    func testFormattingMessagesPlainSkipEmojiInFewShots() {
        let messages = SemanticFormatter.formattingMessages(
            transcript: "随便说一句",
            mode: .structured,
            useEmoji: false
        )
        let withEmoji = messages.contains { ($0["content"] ?? "").contains("📌") || ($0["content"] ?? "").contains("✅") }
        XCTAssertFalse(withEmoji)
    }

    func testCleanFormattingMessagesSkipFewShots() {
        let messages = SemanticFormatter.formattingMessages(transcript: "你好", mode: .clean)
        // Bailian-compatible system + user; no trailing assistant prefill.
        XCTAssertEqual(messages.count, 2)
    }

    func testCustomSystemPromptIsAppendedToFormatterSystemMessage() {
        let messages = SemanticFormatter.formattingMessages(
            transcript: "你好",
            mode: .clean,
            customSystemPrompt: "保持我的个人语气"
        )
        XCTAssertTrue(messages[0]["content"]?.contains("保持我的个人语气") == true)
        XCTAssertEqual(messages.last?["role"], "user")
    }

    func testStripWrappingCodeFence() {
        let raw = """
        ```markdown
        ## 标题

        - 一项
        ```
        """
        XCTAssertEqual(
            SemanticFormatterClient.stripWrappingCodeFence(raw),
            "## 标题\n\n- 一项"
        )
    }

    func testStripLanguageMetaLinesRemovesLeakedDirectives() {
        let raw = """
        [要求的输出语言：简体中文]

        明天三点开会。

        输出语言：Simplified Chinese
        """
        XCTAssertEqual(
            SemanticFormatterClient.stripLanguageMetaLines(raw),
            "明天三点开会。"
        )
    }
}
