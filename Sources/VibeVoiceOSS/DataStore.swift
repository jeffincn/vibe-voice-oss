import Foundation
import SQLite3

/// Thin wrapper around a SQLite3 database stored in Application Support.
/// Confined to `@MainActor` for thread safety — all callers are already on
/// the main actor (UI stores, AppSettings).
@MainActor
final class DataStore {
    static let shared: DataStore = {
        let store = DataStore()
        store.migrate()
        return store
    }()

    private var db: OpaquePointer?

    private init() {
        PersistenceDirectory.ensureExists()
        let path = PersistenceDirectory.url.appendingPathComponent("vibe_voice.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            assertionFailure("DataStore: failed to open database at \(path)")
            return
        }
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA foreign_keys = ON")
    }

    // Singleton lives for the app's lifetime — no deinit needed.

    // MARK: - Migration

    private func migrate() {
        execute("""
            CREATE TABLE IF NOT EXISTS token_usage (
                id TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                stage TEXT NOT NULL,
                model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                total_tokens INTEGER NOT NULL DEFAULT 0,
                cached_input_tokens INTEGER NOT NULL DEFAULT 0,
                reasoning_tokens INTEGER NOT NULL DEFAULT 0,
                audio_input_tokens INTEGER NOT NULL DEFAULT 0,
                audio_output_tokens INTEGER NOT NULL DEFAULT 0,
                audio_seconds REAL
            )
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS pipeline_run (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                outcome TEXT NOT NULL,
                outcome_message TEXT,
                prompt_target TEXT,
                first_partial_ms INTEGER
            )
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS stage_duration (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL REFERENCES pipeline_run(id) ON DELETE CASCADE,
                stage TEXT NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                duration_ms INTEGER NOT NULL,
                detail TEXT
            )
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS recognition_prompt (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL UNIQUE,
                created_at REAL NOT NULL DEFAULT (julianday('now'))
            )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_token_usage_created ON token_usage(created_at)")
        execute("CREATE INDEX IF NOT EXISTS idx_pipeline_run_started ON pipeline_run(started_at)")
        execute("CREATE INDEX IF NOT EXISTS idx_stage_duration_run ON stage_duration(run_id)")
    }

    // MARK: - Token Usage

    func insertTokenUsage(_ record: TokenUsageRecord) {
        let sql = """
            INSERT OR REPLACE INTO token_usage
            (id, created_at, stage, model,
             input_tokens, output_tokens, total_tokens,
             cached_input_tokens, reasoning_tokens,
             audio_input_tokens, audio_output_tokens, audio_seconds)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, record.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, record.stage.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, record.model, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, Int32(record.usage.inputTokens))
        sqlite3_bind_int(stmt, 6, Int32(record.usage.outputTokens))
        sqlite3_bind_int(stmt, 7, Int32(record.usage.totalTokens))
        sqlite3_bind_int(stmt, 8, Int32(record.usage.cachedInputTokens))
        sqlite3_bind_int(stmt, 9, Int32(record.usage.reasoningTokens))
        sqlite3_bind_int(stmt, 10, Int32(record.usage.audioInputTokens))
        sqlite3_bind_int(stmt, 11, Int32(record.usage.audioOutputTokens))
        if let seconds = record.usage.audioSeconds {
            sqlite3_bind_double(stmt, 12, seconds)
        } else {
            sqlite3_bind_null(stmt, 12)
        }
        sqlite3_step(stmt)
    }

    func loadAllTokenUsage() -> [TokenUsageRecord] {
        let sql = "SELECT * FROM token_usage ORDER BY created_at ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var records: [TokenUsageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = columnText(stmt, 0),
                  let id = UUID(uuidString: idStr),
                  let stageStr = columnText(stmt, 2),
                  let stage = UsageStage(rawValue: stageStr),
                  let model = columnText(stmt, 3) else { continue }
            let audioSeconds: Double? = sqlite3_column_type(stmt, 11) == SQLITE_NULL
                ? nil : sqlite3_column_double(stmt, 11)
            let usage = TokenUsage(
                inputTokens: Int(sqlite3_column_int(stmt, 4)),
                outputTokens: Int(sqlite3_column_int(stmt, 5)),
                totalTokens: Int(sqlite3_column_int(stmt, 6)),
                cachedInputTokens: Int(sqlite3_column_int(stmt, 7)),
                reasoningTokens: Int(sqlite3_column_int(stmt, 8)),
                audioInputTokens: Int(sqlite3_column_int(stmt, 9)),
                audioOutputTokens: Int(sqlite3_column_int(stmt, 10)),
                audioSeconds: audioSeconds
            )
            records.append(TokenUsageRecord(
                id: id,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                stage: stage,
                model: model,
                usage: usage
            ))
        }
        return records
    }

    func clearTokenUsage() {
        execute("DELETE FROM token_usage")
    }

    // MARK: - Pipeline Runs (Stage Timing)

    func insertPipelineRun(_ report: PipelineRunReport) {
        execute("BEGIN TRANSACTION")
        let runSQL = """
            INSERT OR REPLACE INTO pipeline_run
            (id, started_at, ended_at, outcome, outcome_message, prompt_target, first_partial_ms)
            VALUES (?,?,?,?,?,?,?)
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, runSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, report.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, report.startedAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, report.endedAt.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 4, report.outcome.rawValue, -1, SQLITE_TRANSIENT)
            bindOptionalText(stmt, 5, report.outcomeMessage)
            bindOptionalText(stmt, 6, report.promptTarget)
            if let ms = report.firstPartialMs {
                sqlite3_bind_int(stmt, 7, Int32(ms))
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // Delete old stage_duration rows for this run_id before inserting fresh ones.
        let delSQL = "DELETE FROM stage_duration WHERE run_id = ?"
        if sqlite3_prepare_v2(db, delSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, report.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        let stageSQL = """
            INSERT INTO stage_duration (run_id, stage, started_at, ended_at, duration_ms, detail)
            VALUES (?,?,?,?,?,?)
        """
        for stage in report.stages {
            if sqlite3_prepare_v2(db, stageSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, report.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, stage.stage.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 3, stage.startedAt.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 4, stage.endedAt.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 5, Int32(stage.durationMs))
                bindOptionalText(stmt, 6, stage.detail)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
        execute("COMMIT")
    }

    func loadAllPipelineRuns() -> [PipelineRunReport] {
        let runSQL = "SELECT * FROM pipeline_run ORDER BY started_at DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, runSQL, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var reports: [PipelineRunReport] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = columnText(stmt, 0),
                  let id = UUID(uuidString: idStr),
                  let outcomeStr = columnText(stmt, 3),
                  let outcome = PipelineRunOutcome(rawValue: outcomeStr) else { continue }
            let stages = loadStages(forRunID: idStr)
            let firstPartialMs: Int? = sqlite3_column_type(stmt, 6) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(stmt, 6))
            reports.append(PipelineRunReport(
                id: id,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                endedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                outcome: outcome,
                outcomeMessage: columnText(stmt, 4),
                stages: stages,
                promptTarget: columnText(stmt, 5),
                firstPartialMs: firstPartialMs
            ))
        }
        return reports
    }

    func clearPipelineRuns() {
        execute("DELETE FROM stage_duration")
        execute("DELETE FROM pipeline_run")
    }

    private func loadStages(forRunID runID: String) -> [StageDuration] {
        let sql = "SELECT stage, started_at, ended_at, duration_ms, detail FROM stage_duration WHERE run_id = ? ORDER BY started_at ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, runID, -1, SQLITE_TRANSIENT)
        var stages: [StageDuration] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let stageStr = columnText(stmt, 0),
                  let stage = PipelineStage(rawValue: stageStr) else { continue }
            stages.append(StageDuration(
                stage: stage,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                endedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                detail: columnText(stmt, 4)
            ))
        }
        return stages
    }

    // MARK: - Recognition Prompts

    func loadRecognitionPrompts() -> [String] {
        let sql = "SELECT word FROM recognition_prompt ORDER BY id ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var words: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let word = columnText(stmt, 0) { words.append(word) }
        }
        return words
    }

    func saveRecognitionPrompts(_ words: [String]) {
        execute("DELETE FROM recognition_prompt")
        let sql = "INSERT OR IGNORE INTO recognition_prompt (word) VALUES (?)"
        for word in words where !word.isEmpty {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    // MARK: - Helpers

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
