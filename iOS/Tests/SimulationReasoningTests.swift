import XCTest
@testable import VibeVoiceMobile

final class SimulationReasoningTests: XCTestCase {
    func testReasoningPromptRequiresEvidenceAndUncertainty() {
        let prompt = SystemTextComposer.reasoningPrompt(for: "甲：你今天怎么怪怪的？乙：没什么。").lowercased()
        XCTAssertTrue(prompt.contains("证据"))
        XCTAssertTrue(prompt.contains("不确定"))
        XCTAssertTrue(prompt.contains("动机"))
    }

    func testReasoningInstructionsDefineStableJSONContract() {
        let instructions = SystemTextComposer.reasoningInstructions
        XCTAssertTrue(instructions.contains("hidden_behavior"))
        XCTAssertTrue(instructions.contains("evidence"))
        XCTAssertTrue(instructions.contains("confidence"))
        XCTAssertTrue(instructions.contains("uncertainties"))
        XCTAssertTrue(instructions.contains("不能把猜测写成确定事实"))
    }

    func testFoundationModelReasoningIsUnavailableBeforeIOS26() {
        if #available(iOS 26.0, *) { return }
        let expectation = expectation(description: "unavailable")
        Task {
            do {
                _ = try await SystemTextComposer.inferHiddenContext("甲：你好。乙：你好。")
                XCTFail("Reasoning must not run on pre-iOS 26")
            } catch {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)
    }

    @available(iOS 26.0, *)
    func testIOS26FoundationModelReasoningContractWhenAvailable() async throws {
        do {
            let output = try await SystemTextComposer.inferHiddenContext(
                "甲：你今天怎么一直站在衣柜门口？乙：没什么。甲：我听到了一声猫叫。"
            )
            XCTAssertFalse(output.isEmpty)
            XCTAssertTrue(output.contains("hidden_behavior") || output.contains("隐藏"))
        } catch SystemTextComposer.ComposerError.unavailable {
            throw XCTSkip("Foundation Models is not available in this simulator/runtime")
        }
    }
}
