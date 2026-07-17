import XCTest
@testable import VibeVoice

final class PromptCompilerTests: XCTestCase {
    func testCodingTargetProfileCapabilities() {
        let profile = PromptTargetKind.codingCodex.profile
        XCTAssertEqual(profile.type, "coding_agent")
        XCTAssertEqual(profile.model, "codex")
        XCTAssertTrue(profile.capabilities.contains("read_repository"))
        XCTAssertTrue(profile.capabilities.contains("edit_files"))
    }

    func testRequestEnvelopeMentionsTwoStagePipeline() {
        let envelope = PromptCompiler.requestEnvelope(
            sourceText: "先找原因不要乱改代码",
            target: .codingCodex
        )
        XCTAssertEqual(envelope["mode"] as? String, "prompt_optimizer")
        let pipeline = envelope["pipeline"] as? [String]
        XCTAssertEqual(pipeline?.first, "intent_understanding")
        XCTAssertTrue(pipeline?.contains("prompt_ir") == true)
        XCTAssertTrue(pipeline?.contains("target_adapter") == true)
    }

    func testIRExtractionMessagesAskForJSONNotFinalPrompt() {
        let messages = PromptCompiler.irExtractionMessages(
            sourceText: "帮我看看这个 bug",
            languageDirective: "Write IR fields in Chinese."
        )
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertTrue(messages.first?["content"]?.contains("Prompt IR") == true)
        XCTAssertTrue(messages.first?["content"]?.contains("Do NOT write the final Prompt") == true
            || messages.first?["content"]?.contains("You do NOT write the final Prompt") == true)

        let assistantIR = messages.filter { $0["role"] == "assistant" && $0["content"]?.contains("task_type") == true }
        XCTAssertFalse(assistantIR.isEmpty)
        XCTAssertTrue(assistantIR.first?["content"]?.contains("\"goal\"") == true)
    }

    func testParseIRFromPlainJSON() throws {
        let json = #"""
        {"task_type":"investigate","goal":"定位回滚原因","context":["偶发"],"current_state":[],"requirements":["先找原因"],"constraints":["不要改代码"],"uncertainties":[],"focus_areas":["乐观更新"],"expected_output":["根因"],"acceptance_criteria":[],"preserve_verbatim":[],"action_mode":"investigate_only"}
        """#
        let ir = try PromptCompiler.parseIR(from: json)
        XCTAssertEqual(ir.taskType, .investigate)
        XCTAssertEqual(ir.actionMode, .investigateOnly)
        XCTAssertEqual(ir.goal, "定位回滚原因")
        XCTAssertEqual(ir.focusAreas, ["乐观更新"])
    }

    func testParseIRFromFencedJSON() throws {
        let raw = """
        ```json
        {"task_type":"implement","goal":"改主色","context":[],"current_state":[],"requirements":[],"constraints":["别动别的"],"uncertainties":[],"focus_areas":[],"expected_output":[],"acceptance_criteria":[],"preserve_verbatim":["primary"],"action_mode":"modify"}
        ```
        """
        let ir = try PromptCompiler.parseIR(from: raw)
        XCTAssertEqual(ir.actionMode, .modify)
        XCTAssertEqual(ir.preserveVerbatim, ["primary"])
    }

    func testParseIRFromProseWrappedJSON() throws {
        let raw = """
        Here is the IR:
        {"task_type":"explain","goal":"解释乐观锁","context":[],"current_state":[],"requirements":["大白话"],"constraints":[],"uncertainties":[],"focus_areas":[],"expected_output":[],"acceptance_criteria":[],"preserve_verbatim":[],"action_mode":"advise"}
        Thanks.
        """
        let ir = try PromptCompiler.parseIR(from: raw)
        XCTAssertEqual(ir.taskType, .explain)
        XCTAssertEqual(ir.goal, "解释乐观锁")
    }

    func testCompileInvestigateOnlyForCodex() throws {
        let json = PromptCompiler.irFewShots[0].irJSON
        let prompt = try PromptCompiler.compile(irRaw: json, target: .codingCodex)
        XCTAssertTrue(prompt.contains("不要直接改代码") || prompt.contains("不要直接修改代码"))
        XCTAssertTrue(prompt.contains("批量") || prompt.contains("回滚") || prompt.contains("定位"))
        XCTAssertTrue(prompt.contains("Codex"))
        XCTAssertTrue(prompt.contains("重点检查") || prompt.contains("乐观更新"))
    }

    func testCompilePreservesUncertainty() throws {
        let json = PromptCompiler.irFewShots[2].irJSON
        let prompt = try PromptCompiler.compile(irRaw: json, target: .codingCodex)
        XCTAssertTrue(prompt.contains("不确定性") || prompt.contains("可能"))
        XCTAssertTrue(prompt.contains("筛选"))
    }

    func testChatAdapterRendersSourceForGenerate() throws {
        let json = PromptCompiler.irFewShots[3].irJSON
        let prompt = try PromptCompiler.compile(irRaw: json, target: .chat)
        XCTAssertTrue(prompt.contains("客户邮件") || prompt.contains("润色"))
        XCTAssertTrue(prompt.contains("我们这周会把修改稿发给你们"))
    }

    func testImageAdapterFlattens() throws {
        let json = #"""
        {"task_type":"generate","goal":"生成一张安静的夜晚海边场景图像","context":[],"current_state":[],"requirements":["夜晚海边","人很少","氛围安静"],"constraints":["不要卡通"],"uncertainties":[],"focus_areas":["soft moonlight"],"expected_output":["image prompt"],"acceptance_criteria":[],"preserve_verbatim":[],"action_mode":"generate"}
        """#
        let prompt = try PromptCompiler.compile(irRaw: json, target: .image)
        XCTAssertTrue(prompt.contains("海边") || prompt.lowercased().contains("night") || prompt.contains("安静"))
        XCTAssertTrue(prompt.contains("卡通") || prompt.lowercased().contains("cartoon") || prompt.contains("不要"))
    }

    func testSameIRDifferentTargets() throws {
        let json = PromptCompiler.irFewShots[0].irJSON
        let codex = try PromptCompiler.compile(irRaw: json, target: .codingCodex)
        let research = try PromptCompiler.compile(irRaw: json, target: .research)
        XCTAssertNotEqual(codex, research)
        XCTAssertTrue(codex.contains("Codex"))
        XCTAssertTrue(research.contains("调研") || research.contains("来源"))
    }

    func testEmptyIRThrows() {
        XCTAssertThrowsError(try PromptCompiler.parseIR(from: #"{"goal":"","task_type":"other","action_mode":"advise"}"#))
    }

    func testParseIRToleratesStringArraysAndEnumAliases() throws {
        let json = #"""
        {
          "task_type": "debug",
          "goal": "定位超时",
          "context": "短输入也会很慢",
          "current_state": [],
          "requirements": "先确认错误原因",
          "constraints": ["不要扩大范围"],
          "uncertainties": [],
          "focus_areas": "Prompt IR 解码",
          "expected_output": ["根因"],
          "acceptance_criteria": [],
          "preserve_verbatim": "from",
          "action_mode": "investigate"
        }
        """#
        let ir = try PromptCompiler.parseIR(from: json)
        XCTAssertEqual(ir.taskType, .investigate)
        XCTAssertEqual(ir.actionMode, .investigateOnly)
        XCTAssertEqual(ir.context, ["短输入也会很慢"])
        XCTAssertEqual(ir.requirements, ["先确认错误原因"])
        XCTAssertEqual(ir.focusAreas, ["Prompt IR 解码"])
        XCTAssertEqual(ir.preserveVerbatim, ["from"])
    }

    func testParseIRTruncatedJSONGivesReadableError() {
        XCTAssertThrowsError(try PromptCompiler.parseIR(from: #"{"task_type":"investigate","goal":"断"#)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("无法解析") || message.contains("损坏") || message.contains("JSON"))
            XCTAssertFalse(message.contains("CodingKeys(stringValue:"))
        }
    }

    func testIRExtractionMessagesStayCompact() {
        let messages = PromptCompiler.irExtractionMessages(
            sourceText: "短输入",
            languageDirective: "Chinese"
        )
        let assistantIR = messages.filter { $0["role"] == "assistant" && $0["content"]?.contains("task_type") == true }
        XCTAssertEqual(assistantIR.count, 4)
        let totalIRChars = assistantIR.reduce(0) { $0 + ($1["content"]?.count ?? 0) }
        XCTAssertLessThan(totalIRChars, 2800, "few-shot IR payloads should stay compact for latency")
    }
}
