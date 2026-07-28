import Foundation

/// Which post-processing stages a recording session runs, derived from the output
/// mode the user started it with.
///
/// `finishRecording` and `finishVoicePipeline` each carried their own copy of this
/// switch, plus a third copy for the stage-timing label. Adding a mode meant editing
/// all three, and a mode handled in one but not another silently took the `nil`
/// branch — the session would quietly process as if no mode had been chosen.
struct OutputModePlan: Equatable, Sendable {
    /// The settings the plan reads. Passing these in rather than `AppSettings` keeps
    /// the derivation testable without building the whole settings object.
    struct Capabilities: Equatable, Sendable {
        var llmAvailable: Bool
        var structuredOutputEnabled: Bool
        var hasCustomFormattingPrompt: Bool
        var promptOptimizeEnabled: Bool
        var promptTargetLabel: String
        var roleModeEnabled: Bool

        init(
            llmAvailable: Bool,
            structuredOutputEnabled: Bool,
            hasCustomFormattingPrompt: Bool,
            promptOptimizeEnabled: Bool,
            promptTargetLabel: String,
            roleModeEnabled: Bool = false
        ) {
            self.llmAvailable = llmAvailable
            self.structuredOutputEnabled = structuredOutputEnabled
            self.hasCustomFormattingPrompt = hasCustomFormattingPrompt
            self.promptOptimizeEnabled = promptOptimizeEnabled
            self.promptTargetLabel = promptTargetLabel
            self.roleModeEnabled = roleModeEnabled
        }
    }

    let structuredOutput: Bool
    let promptOptimize: Bool
    let smartRoute: Bool
    /// English mode translates to English only and drops the original text.
    let englishOnly: Bool
    /// Prompt target for the stage-timing report; nil when no prompt stage will run.
    let promptTargetLabel: String?

    var includeOriginal: Bool { !englishOnly }

    init(mode: RecordingOutputMode?, capabilities: Capabilities) {
        let llm = capabilities.llmAvailable
        englishOnly = mode == .english

        switch mode {
        case .conversation:
            structuredOutput = llm && capabilities.roleModeEnabled
            promptOptimize = false
            smartRoute = false
            promptTargetLabel = nil
        case .english:
            structuredOutput = false
            promptOptimize = false
            smartRoute = false
            promptTargetLabel = nil
        case .structured:
            structuredOutput = llm
            promptOptimize = false
            smartRoute = false
            promptTargetLabel = nil
        case .prompt:
            structuredOutput = false
            promptOptimize = llm
            smartRoute = false
            promptTargetLabel = llm ? capabilities.promptTargetLabel : nil
        case .smartRoute:
            structuredOutput = false
            promptOptimize = false
            smartRoute = llm
            promptTargetLabel = nil
        case .none:
            // No explicit mode: fall back to whatever the user left switched on.
            structuredOutput = llm
                && (capabilities.structuredOutputEnabled
                    || capabilities.hasCustomFormattingPrompt
                    || capabilities.roleModeEnabled)
            promptOptimize = llm && capabilities.promptOptimizeEnabled
            smartRoute = false
            promptTargetLabel = promptOptimize ? capabilities.promptTargetLabel : nil
        }
    }

    func targetLanguages(fallback: [TargetLanguage]) -> [TargetLanguage] {
        englishOnly ? [TargetLanguage.resolve(id: "en")] : fallback
    }
}
