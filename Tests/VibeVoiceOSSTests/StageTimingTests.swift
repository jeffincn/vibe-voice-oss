import XCTest
@testable import VibeVoiceOSS

@MainActor
final class StageTimingTests: XCTestCase {
    func testRecordsPerStageDurations() async throws {
        let store = StageTimingStore()
        store.beginSession(promptTarget: "Codex")
        store.enter(.recording)
        try await Task.sleep(for: .milliseconds(20))
        store.enter(.transcribing)
        try await Task.sleep(for: .milliseconds(15))
        store.enter(.optimizing, detail: "Codex")
        try await Task.sleep(for: .milliseconds(10))
        store.finishSession(outcome: .success)

        let session = try XCTUnwrap(store.latestSession)
        XCTAssertEqual(session.outcome, .success)
        XCTAssertEqual(session.promptTarget, "Codex")
        XCTAssertEqual(session.stages.map(\.stage), [.recording, .transcribing, .optimizing])
        XCTAssertEqual(session.stages.last?.detail, "Codex")
        XCTAssertGreaterThan(session.totalMs, 0)
        XCTAssertEqual(session.stages.count, 3)
    }

    func testCSVContainsStageRows() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(1.5)
        let report = PipelineRunReport(
            id: UUID(),
            startedAt: started,
            endedAt: ended,
            outcome: .success,
            outcomeMessage: nil,
            stages: [
                StageDuration(stage: .transcribing, startedAt: started, endedAt: started.addingTimeInterval(0.8)),
                StageDuration(
                    stage: .optimizing,
                    startedAt: started.addingTimeInterval(0.8),
                    endedAt: ended,
                    detail: "Claude Code"
                )
            ],
            promptTarget: "Claude Code",
            firstPartialMs: 120
        )
        let csv = StageTimingExport.csv(sessions: [report])
        XCTAssertTrue(csv.contains("session_id,started_at"))
        XCTAssertTrue(csv.contains("transcribing"))
        XCTAssertTrue(csv.contains("optimizing"))
        XCTAssertTrue(csv.contains("Claude Code"))
    }

    func testHTMLContainsLabelsAndTotals() {
        let started = Date()
        let report = PipelineRunReport(
            id: UUID(),
            startedAt: started,
            endedAt: started.addingTimeInterval(2),
            outcome: .failed,
            outcomeMessage: "timeout",
            stages: [
                StageDuration(stage: .structuring, startedAt: started, endedAt: started.addingTimeInterval(2))
            ],
            promptTarget: nil,
            firstPartialMs: nil
        )
        let html = StageTimingExport.html(sessions: [report])
        XCTAssertTrue(html.contains("阶段耗时报告"))
        XCTAssertTrue(html.contains("整理"))
        XCTAssertTrue(html.contains("失败"))
        XCTAssertTrue(html.contains("timeout"))
    }

    func testSupersedeClosesPreviousSession() {
        let store = StageTimingStore()
        store.beginSession()
        store.enter(.transcribing)
        store.beginSession(promptTarget: "Grok")
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.outcome, .superseded)
        store.enter(.recording)
        store.finishSession(outcome: .success)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions.first?.promptTarget, "Grok")
    }
}
