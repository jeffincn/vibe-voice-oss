import XCTest
@testable import VibeVoiceOSS

@MainActor
final class DataStoreTests: XCTestCase {
    // MARK: - Token usage

    func testTokenUsageRoundTripsEveryField() throws {
        try withStore { store, _ in
            let record = TokenUsageRecord(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                stage: .translation,
                model: "qwen-max",
                usage: TokenUsage(
                    inputTokens: 11,
                    outputTokens: 22,
                    totalTokens: 33,
                    cachedInputTokens: 4,
                    reasoningTokens: 5,
                    audioInputTokens: 6,
                    audioOutputTokens: 7,
                    audioSeconds: 8.5
                )
            )
            store.insertTokenUsage(record)

            let loaded = try XCTUnwrap(store.loadAllTokenUsage().first)
            XCTAssertEqual(loaded.id, record.id)
            XCTAssertEqual(loaded.createdAt, record.createdAt)
            XCTAssertEqual(loaded.stage, record.stage)
            XCTAssertEqual(loaded.model, record.model)
            XCTAssertEqual(loaded.usage, record.usage)
        }
    }

    func testTokenUsageKeepsNilAudioSecondsDistinctFromZero() throws {
        try withStore { store, _ in
            var usage = TokenUsage()
            usage.inputTokens = 1
            store.insertTokenUsage(
                TokenUsageRecord(id: UUID(), createdAt: Date(), stage: .transcription, model: "m", usage: usage)
            )
            let loaded = try XCTUnwrap(store.loadAllTokenUsage().first)
            XCTAssertNil(loaded.usage.audioSeconds)
        }
    }

    func testTokenUsageComesBackOldestFirst() throws {
        try withStore { store, _ in
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            for offset in [30.0, 10.0, 20.0] {
                store.insertTokenUsage(
                    TokenUsageRecord(
                        id: UUID(),
                        createdAt: base.addingTimeInterval(offset),
                        stage: .structuring,
                        model: "m",
                        usage: TokenUsage()
                    )
                )
            }
            let dates = store.loadAllTokenUsage().map(\.createdAt)
            XCTAssertEqual(dates, dates.sorted())
        }
    }

    // MARK: - Pipeline runs

    func testPipelineRunRoundTripsWithItsStages() throws {
        try withStore { store, _ in
            let report = Self.makeReport(stageCount: 3, firstPartialMs: 120, promptTarget: "Codex")
            store.insertPipelineRun(report)

            let loaded = try XCTUnwrap(store.loadAllPipelineRuns().first)
            XCTAssertEqual(loaded.id, report.id)
            XCTAssertEqual(loaded.outcome, .success)
            XCTAssertEqual(loaded.promptTarget, "Codex")
            XCTAssertEqual(loaded.firstPartialMs, 120)
            XCTAssertEqual(loaded.stages.map(\.stage), report.stages.map(\.stage))
            XCTAssertEqual(loaded.stages.map(\.durationMs), report.stages.map(\.durationMs))
            XCTAssertEqual(loaded.stages.map(\.detail), report.stages.map(\.detail))
        }
    }

    func testNilFirstPartialSurvivesTheRoundTrip() throws {
        try withStore { store, _ in
            store.insertPipelineRun(Self.makeReport(stageCount: 1, firstPartialMs: nil, promptTarget: nil))
            let loaded = try XCTUnwrap(store.loadAllPipelineRuns().first)
            XCTAssertNil(loaded.firstPartialMs)
            XCTAssertNil(loaded.promptTarget)
        }
    }

    /// Re-reporting the same run used to append its stages a second time: the run row
    /// was REPLACEd while the stage rows were only ever inserted.
    func testReinsertingARunReplacesItsStagesRatherThanAppending() throws {
        try withStore { store, _ in
            let report = Self.makeReport(stageCount: 2, firstPartialMs: nil, promptTarget: nil)
            store.insertPipelineRun(report)
            store.insertPipelineRun(report)

            let runs = store.loadAllPipelineRuns()
            XCTAssertEqual(runs.count, 1)
            XCTAssertEqual(runs.first?.stages.count, 2)
        }
    }

    func testPipelineRunsComeBackNewestFirst() throws {
        try withStore { store, _ in
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            for offset in [0.0, 60.0, 30.0] {
                store.insertPipelineRun(
                    Self.makeReport(
                        stageCount: 1,
                        firstPartialMs: nil,
                        promptTarget: nil,
                        startedAt: base.addingTimeInterval(offset)
                    )
                )
            }
            let dates = store.loadAllPipelineRuns().map(\.startedAt)
            XCTAssertEqual(dates, dates.sorted(by: >))
        }
    }

    func testClearingRunsTakesTheStageRowsWithThem() throws {
        try withStore { store, _ in
            let report = Self.makeReport(stageCount: 3, firstPartialMs: nil, promptTarget: nil)
            store.insertPipelineRun(report)
            store.clearPipelineRuns()
            XCTAssertTrue(store.loadAllPipelineRuns().isEmpty)

            // Reusing the id: orphaned stage rows would reattach to this run.
            store.insertPipelineRun(
                Self.makeReport(id: report.id, stageCount: 1, firstPartialMs: nil, promptTarget: nil)
            )
            XCTAssertEqual(store.loadAllPipelineRuns().first?.stages.count, 1)
        }
    }

    // MARK: - Recognition prompts

    func testRecognitionPromptsKeepInsertionOrderAndDropBlanks() throws {
        try withStore { store, _ in
            store.saveRecognitionPrompts(["Kubernetes", "", "SwiftUI", "Core Audio"])
            XCTAssertEqual(store.loadRecognitionPrompts(), ["Kubernetes", "SwiftUI", "Core Audio"])
        }
    }

    func testSavingPromptsReplacesTheWholeList() throws {
        try withStore { store, _ in
            store.saveRecognitionPrompts(["one", "two"])
            store.saveRecognitionPrompts(["three"])
            XCTAssertEqual(store.loadRecognitionPrompts(), ["three"])
        }
    }

    func testDuplicatePromptsAreStoredOnce() throws {
        try withStore { store, _ in
            store.saveRecognitionPrompts(["dup", "dup", "other"])
            XCTAssertEqual(store.loadRecognitionPrompts(), ["dup", "other"])
        }
    }

    // MARK: - Durability

    func testDataSurvivesReopeningTheDatabase() throws {
        try withStore { store, directory in
            store.saveRecognitionPrompts(["persisted"])
            store.insertPipelineRun(Self.makeReport(stageCount: 1, firstPartialMs: 7, promptTarget: nil))
            store.close()

            let reopened = DataStore(directory: directory)
            defer { reopened.close() }
            XCTAssertEqual(reopened.loadRecognitionPrompts(), ["persisted"])
            XCTAssertEqual(reopened.loadAllPipelineRuns().first?.firstPartialMs, 7)
        }
    }

    // MARK: - Helpers

    /// Each test gets its own database file; `close()` is idempotent so tests that
    /// reopen the store on purpose can call it themselves.
    private func withStore(_ body: (DataStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(directory: directory)
        defer {
            store.close()
            try? FileManager.default.removeItem(at: directory)
        }
        try body(store, directory)
    }

    private static func makeReport(
        id: UUID = UUID(),
        stageCount: Int,
        firstPartialMs: Int?,
        promptTarget: String?,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> PipelineRunReport {
        let order: [PipelineStage] = [.recording, .transcribing, .structuring, .translating]
        let stages = (0..<stageCount).map { index in
            StageDuration(
                stage: order[index % order.count],
                startedAt: startedAt.addingTimeInterval(Double(index)),
                endedAt: startedAt.addingTimeInterval(Double(index) + 0.5),
                detail: index == 0 ? nil : "step \(index)"
            )
        }
        return PipelineRunReport(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(stageCount)),
            outcome: .success,
            outcomeMessage: nil,
            stages: stages,
            promptTarget: promptTarget,
            firstPartialMs: firstPartialMs
        )
    }
}
