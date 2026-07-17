import Foundation

/// Discrete processing stages timed across one voice → output pipeline run.
enum PipelineStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case recording
    case finalizing
    case transcribing
    case structuring
    case translating
    case optimizing
    case paste

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recording: "录音"
        case .finalizing: "收敛识别"
        case .transcribing: "转写"
        case .structuring: "整理"
        case .translating: "翻译"
        case .optimizing: "输出 Prompt"
        case .paste: "写入输入框"
        }
    }

    var csvKey: String { rawValue }
}

struct StageDuration: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(stage.rawValue)-\(startedAt.timeIntervalSince1970)" }
    let stage: PipelineStage
    let startedAt: Date
    let endedAt: Date
    let durationMs: Int
    /// Optional nested detail (e.g. Codex / Claude Code while optimizing).
    let detail: String?

    init(stage: PipelineStage, startedAt: Date, endedAt: Date, detail: String? = nil) {
        self.stage = stage
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = max(0, Int((endedAt.timeIntervalSince(startedAt) * 1000).rounded()))
        self.detail = detail
    }
}

enum PipelineRunOutcome: String, Codable, Sendable {
    case success
    case failed
    case cancelled
    case superseded

    var label: String {
        switch self {
        case .success: "成功"
        case .failed: "失败"
        case .cancelled: "已取消"
        case .superseded: "已覆盖"
        }
    }
}

struct PipelineRunReport: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let outcome: PipelineRunOutcome
    let outcomeMessage: String?
    let stages: [StageDuration]
    let promptTarget: String?
    /// Milliseconds from session start to first Streaming partial (nil if never received).
    let firstPartialMs: Int?

    var totalMs: Int {
        stages.reduce(0) { $0 + $1.durationMs }
    }

    var formattedTotal: String {
        StageTimingFormatter.formatMs(totalMs)
    }
}

enum StageTimingFormatter {
    static func formatMs(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        let seconds = Double(ms) / 1000
        if seconds < 60 {
            return String(format: "%.2f s", seconds)
        }
        let minutes = Int(seconds) / 60
        let rem = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d m %.1f s", minutes, rem)
    }

    static func isoString(from date: Date) -> String {
        date.formatted(.iso8601.dateTimeSeparator(.standard).timeZone(separator: .omitted))
    }

    static func displayString(from date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
                .locale(Locale(identifier: "zh_CN"))
        )
    }
}

/// Records wall-clock duration for each pipeline stage and keeps recent run history.
@MainActor
final class StageTimingStore: ObservableObject {
    static let maxSessions = 100

    @Published private(set) var sessions: [PipelineRunReport] = []

    private var sessionID: UUID?
    private var sessionStartedAt: Date?
    private var openStage: PipelineStage?
    private var openStageStartedAt: Date?
    private var openStageDetail: String?
    private var buildingStages: [StageDuration] = []
    private var promptTarget: String?
    private var firstPartialMs: Int?

    var latestSession: PipelineRunReport? { sessions.first }

    var hasActiveSession: Bool { sessionID != nil }

    // MARK: - Lifecycle

    func beginSession(promptTarget: String? = nil) {
        // Supersede any open session (e.g. user re-triggered recording mid-pipeline).
        if sessionID != nil {
            finishSession(outcome: .superseded, message: "新的录音覆盖了进行中的任务")
        }
        sessionID = UUID()
        sessionStartedAt = Date()
        buildingStages = []
        openStage = nil
        openStageStartedAt = nil
        openStageDetail = nil
        firstPartialMs = nil
        self.promptTarget = promptTarget
    }

    /// Record time-to-first-partial once per session (Streaming UX metric).
    func markFirstPartial() {
        guard firstPartialMs == nil, let started = sessionStartedAt else { return }
        firstPartialMs = max(0, Int((Date().timeIntervalSince(started) * 1000).rounded()))
    }

    /// Close current stage (if any) and open `stage`.
    func enter(_ stage: PipelineStage, detail: String? = nil) {
        guard sessionID != nil else {
            beginSession(promptTarget: promptTarget)
            enter(stage, detail: detail)
            return
        }
        closeOpenStage(at: Date())
        openStage = stage
        openStageStartedAt = Date()
        openStageDetail = detail
    }

    func finishSession(outcome: PipelineRunOutcome, message: String? = nil) {
        guard let id = sessionID, let started = sessionStartedAt else { return }
        closeOpenStage(at: Date())
        let report = PipelineRunReport(
            id: id,
            startedAt: started,
            endedAt: Date(),
            outcome: outcome,
            outcomeMessage: message,
            stages: buildingStages,
            promptTarget: promptTarget,
            firstPartialMs: firstPartialMs
        )
        sessions.insert(report, at: 0)
        if sessions.count > Self.maxSessions {
            sessions = Array(sessions.prefix(Self.maxSessions))
        }
        resetBuilder()
    }

    func clearHistory() {
        sessions.removeAll()
    }

    private func closeOpenStage(at date: Date) {
        guard let stage = openStage, let started = openStageStartedAt else { return }
        buildingStages.append(
            StageDuration(
                stage: stage,
                startedAt: started,
                endedAt: date,
                detail: openStageDetail
            )
        )
        openStage = nil
        openStageStartedAt = nil
        openStageDetail = nil
    }

    private func resetBuilder() {
        sessionID = nil
        sessionStartedAt = nil
        openStage = nil
        openStageStartedAt = nil
        openStageDetail = nil
        buildingStages = []
        promptTarget = nil
        firstPartialMs = nil
    }

    // MARK: - Export

    func exportCSV(sessions selected: [PipelineRunReport]? = nil) -> String {
        StageTimingExport.csv(sessions: selected ?? sessions)
    }

    func exportHTML(sessions selected: [PipelineRunReport]? = nil) -> String {
        StageTimingExport.html(sessions: selected ?? sessions)
    }
}

enum StageTimingExport {
    static func csv(sessions: [PipelineRunReport]) -> String {
        var lines: [String] = [
            "session_id,started_at,ended_at,outcome,prompt_target,first_partial_ms,stage,stage_detail,duration_ms,duration_label"
        ]
        for session in sessions {
            let started = StageTimingFormatter.isoString(from: session.startedAt)
            let ended = StageTimingFormatter.isoString(from: session.endedAt)
            let target = csvEscape(session.promptTarget ?? "")
            let firstPartial = session.firstPartialMs.map(String.init) ?? ""
            if session.stages.isEmpty {
                lines.append([
                    session.id.uuidString,
                    started,
                    ended,
                    session.outcome.rawValue,
                    target,
                    firstPartial,
                    "",
                    "",
                    "0",
                    ""
                ].joined(separator: ","))
                continue
            }
            for stage in session.stages {
                lines.append([
                    session.id.uuidString,
                    started,
                    ended,
                    session.outcome.rawValue,
                    target,
                    firstPartial,
                    stage.stage.csvKey,
                    csvEscape(stage.detail ?? ""),
                    String(stage.durationMs),
                    csvEscape(StageTimingFormatter.formatMs(stage.durationMs))
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func html(sessions: [PipelineRunReport]) -> String {
        let rows = sessions.map { session -> String in
            let stageRows = session.stages.map { stage in
                let detail = stage.detail.map { " · \($0)" } ?? ""
                return """
                <tr>
                  <td>\(htmlEscape(stage.stage.label))\(htmlEscape(detail))</td>
                  <td class="num">\(stage.durationMs)</td>
                  <td class="num">\(htmlEscape(StageTimingFormatter.formatMs(stage.durationMs)))</td>
                </tr>
                """
            }.joined()

            let stageTable = session.stages.isEmpty
                ? "<p class=\"muted\">无阶段数据</p>"
                : """
                <table>
                  <thead><tr><th>阶段</th><th>毫秒</th><th>时长</th></tr></thead>
                  <tbody>\(stageRows)</tbody>
                </table>
                """

            return """
            <section class="run">
              <h2>\(htmlEscape(StageTimingFormatter.displayString(from: session.startedAt)))</h2>
              <p>
                结果：<strong>\(htmlEscape(session.outcome.label))</strong>
                · 合计 <strong>\(htmlEscape(session.formattedTotal))</strong>
                \(session.promptTarget.map { "· 目标 Agent：<strong>\(htmlEscape($0))</strong>" } ?? "")
                \(session.firstPartialMs.map { "· 首 partial：<strong>\(htmlEscape(StageTimingFormatter.formatMs($0)))</strong>" } ?? "")
              </p>
              \(session.outcomeMessage.map { "<p class=\"muted\">\(htmlEscape($0))</p>" } ?? "")
              \(stageTable)
            </section>
            """
        }.joined(separator: "\n")

        let generated = StageTimingFormatter.displayString(from: Date())
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8"/>
          <title>Vibe Voice OSS 阶段耗时报告</title>
          <style>
            :root { color-scheme: light dark; }
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; line-height: 1.45; }
            h1 { font-size: 1.4rem; margin-bottom: 0.25rem; }
            .meta { color: #666; margin-bottom: 1.5rem; }
            .run { border: 1px solid #ddd; border-radius: 10px; padding: 16px 18px; margin-bottom: 16px; }
            h2 { font-size: 1.05rem; margin: 0 0 8px; }
            table { width: 100%; border-collapse: collapse; margin-top: 8px; }
            th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid #eee; font-size: 0.92rem; }
            th { font-weight: 600; }
            td.num { font-variant-numeric: tabular-nums; text-align: right; }
            .muted { color: #777; font-size: 0.9rem; }
          </style>
        </head>
        <body>
          <h1>Vibe Voice OSS 阶段耗时报告</h1>
          <p class="meta">生成于 \(htmlEscape(generated)) · 共 \(sessions.count) 次运行</p>
          \(rows.isEmpty ? "<p class=\"muted\">暂无记录</p>" : rows)
        </body>
        </html>
        """
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
