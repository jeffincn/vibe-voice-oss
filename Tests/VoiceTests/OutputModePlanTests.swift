import XCTest
@testable import VibeVoiceOSS

final class OutputModePlanTests: XCTestCase {
    private func capabilities(
        llmAvailable: Bool = true,
        structuredOutputEnabled: Bool = false,
        hasCustomFormattingPrompt: Bool = false,
        promptOptimizeEnabled: Bool = false
    ) -> OutputModePlan.Capabilities {
        OutputModePlan.Capabilities(
            llmAvailable: llmAvailable,
            structuredOutputEnabled: structuredOutputEnabled,
            hasCustomFormattingPrompt: hasCustomFormattingPrompt,
            promptOptimizeEnabled: promptOptimizeEnabled,
            promptTargetLabel: "Codex"
        )
    }

    func testExplicitModesEachEnableExactlyOneStage() {
        let expectations: [(RecordingOutputMode, structured: Bool, prompt: Bool, smart: Bool)] = [
            (.conversation, false, false, false),
            (.english, false, false, false),
            (.structured, true, false, false),
            (.prompt, false, true, false),
            (.smartRoute, false, false, true),
        ]
        for expectation in expectations {
            let plan = OutputModePlan(mode: expectation.0, capabilities: capabilities())
            XCTAssertEqual(plan.structuredOutput, expectation.structured, "\(expectation.0)")
            XCTAssertEqual(plan.promptOptimize, expectation.prompt, "\(expectation.0)")
            XCTAssertEqual(plan.smartRoute, expectation.smart, "\(expectation.0)")
        }
    }

    /// Every stage goes through an LLM. Without one configured, an explicit mode must
    /// degrade to plain transcription rather than queue a request that cannot run.
    func testNoStageRunsWithoutAnLLM() {
        for mode in RecordingOutputMode.allCases {
            let plan = OutputModePlan(
                mode: mode,
                capabilities: capabilities(
                    llmAvailable: false,
                    structuredOutputEnabled: true,
                    hasCustomFormattingPrompt: true,
                    promptOptimizeEnabled: true
                )
            )
            XCTAssertFalse(plan.structuredOutput, "\(mode)")
            XCTAssertFalse(plan.promptOptimize, "\(mode)")
            XCTAssertFalse(plan.smartRoute, "\(mode)")
            XCTAssertNil(plan.promptTargetLabel, "\(mode)")
        }
    }

    // MARK: - No explicit mode

    func testWithoutAModeTheStandingSettingsDecide() {
        let plan = OutputModePlan(
            mode: nil,
            capabilities: capabilities(structuredOutputEnabled: true, promptOptimizeEnabled: true)
        )
        XCTAssertTrue(plan.structuredOutput)
        XCTAssertTrue(plan.promptOptimize)
        XCTAssertFalse(plan.smartRoute)
    }

    func testACustomFormattingPromptTurnsStructuringOnByItself() {
        let plan = OutputModePlan(mode: nil, capabilities: capabilities(hasCustomFormattingPrompt: true))
        XCTAssertTrue(plan.structuredOutput)
    }

    func testWithoutAModeAndWithNothingEnabledNothingRuns() {
        let plan = OutputModePlan(mode: nil, capabilities: capabilities())
        XCTAssertFalse(plan.structuredOutput)
        XCTAssertFalse(plan.promptOptimize)
        XCTAssertFalse(plan.smartRoute)
        XCTAssertNil(plan.promptTargetLabel)
    }

    // MARK: - Stage timing label

    func testPromptModeReportsTheTargetItWillOptimizeFor() {
        XCTAssertEqual(
            OutputModePlan(mode: .prompt, capabilities: capabilities()).promptTargetLabel,
            "Codex"
        )
    }

    func testTheLabelIsOnlySetWhenAPromptStageActuallyRuns() {
        XCTAssertNil(OutputModePlan(mode: .structured, capabilities: capabilities()).promptTargetLabel)
        XCTAssertNil(OutputModePlan(mode: .smartRoute, capabilities: capabilities()).promptTargetLabel)
        XCTAssertNil(
            OutputModePlan(mode: nil, capabilities: capabilities(promptOptimizeEnabled: false))
                .promptTargetLabel
        )
        XCTAssertEqual(
            OutputModePlan(mode: nil, capabilities: capabilities(promptOptimizeEnabled: true))
                .promptTargetLabel,
            "Codex"
        )
    }

    // MARK: - Languages

    func testEnglishModeReplacesTheTargetsAndDropsTheOriginal() {
        let plan = OutputModePlan(mode: .english, capabilities: capabilities())
        let fallback = [TargetLanguage.resolve(id: "ja")]

        XCTAssertTrue(plan.englishOnly)
        XCTAssertFalse(plan.includeOriginal)
        XCTAssertEqual(plan.targetLanguages(fallback: fallback), [TargetLanguage.resolve(id: "en")])
    }

    func testEveryOtherModeKeepsTheConfiguredTargetsAndTheOriginal() {
        let fallback = [TargetLanguage.resolve(id: "ja"), TargetLanguage.resolve(id: "en")]
        for mode in RecordingOutputMode.allCases where mode != .english {
            let plan = OutputModePlan(mode: mode, capabilities: capabilities())
            XCTAssertTrue(plan.includeOriginal, "\(mode)")
            XCTAssertEqual(plan.targetLanguages(fallback: fallback), fallback, "\(mode)")
        }
        let noMode = OutputModePlan(mode: nil, capabilities: capabilities())
        XCTAssertTrue(noMode.includeOriginal)
        XCTAssertEqual(noMode.targetLanguages(fallback: fallback), fallback)
    }
}
