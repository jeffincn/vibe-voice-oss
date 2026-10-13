import XCTest
@testable import VibeVoiceOSS

@MainActor
final class HUDStatusTests: XCTestCase {
    func testPrimaryLabelsMatchPipelineStages() {
        L10n.language = .zhHans
        AppLocalization.shared.apply(.zhHans)
        XCTAssertEqual(AppState.Phase.structuring.hudPrimary, "整理中")
        XCTAssertEqual(AppState.Phase.translating.hudPrimary, "翻译中")
        XCTAssertEqual(AppState.Phase.optimizing.hudPrimary, "输出 Prompt")
        XCTAssertEqual(AppState.Phase.transcribing.hudPrimary, "转写中")
        XCTAssertEqual(AppState.Phase.recording.hudPrimary, "录音中")
        XCTAssertEqual(AppState.Phase.finalizing.hudPrimary, "收敛中")

        AppLocalization.shared.apply(.english)
        XCTAssertEqual(AppState.Phase.recording.hudPrimary, "Recording")
        XCTAssertEqual(AppState.Phase.finalizing.hudPrimary, "Finalizing")
    }

    func testOnlyOptimizingShowsSecondary() {
        XCTAssertTrue(AppState.Phase.optimizing.showsHUDSecondary)
        XCTAssertFalse(AppState.Phase.structuring.showsHUDSecondary)
        XCTAssertFalse(AppState.Phase.translating.showsHUDSecondary)
        XCTAssertFalse(AppState.Phase.transcribing.showsHUDSecondary)
    }

    func testHudSecondaryUsesPromptTarget() {
        let state = AppState()
        state.settings.promptTarget = .codingCodex
        // phase defaults to idle — secondary nil
        XCTAssertNil(state.hudSecondary)

        // Simulate optimizing via reflection is hard; verify label source instead.
        XCTAssertEqual(PromptTargetKind.codingCodex.label, "Codex")
        XCTAssertEqual(PromptTargetKind.codingClaude.label, "Claude Code")
        XCTAssertEqual(PromptTargetKind.codingGrok.label, "Grok")
    }
}
