import Foundation
import OSLog
import SQLite3

/// Thin wrapper around a SQLite3 database stored in Application Support.
/// Confined to `@MainActor` for thread safety — all callers are already on
/// the main actor (UI stores, AppSettings).
@MainActor
final class DataStore {
    static let shared = DataStore()

    private var db: OpaquePointer?

    private convenience init() {
        PersistenceDirectory.ensureExists()
        self.init(directory: PersistenceDirectory.url)
    }

    /// Opens an independent database under `directory`. Production code goes through
    /// `shared`; this exists so tests can run against a temporary directory.
    init(directory: URL) {
        let path = directory.appendingPathComponent("vibe_voice.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            assertionFailure("DataStore: failed to open database at \(path)")
            return
        }
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA foreign_keys = ON")
        migrate()
    }

    /// The shared store lives for the app's lifetime and never needs this. Instances
    /// opened against a temporary directory do, otherwise the connection outlives them.
    func close() {
        guard let db else { return }
        sqlite3_close_v2(db)
        self.db = nil
    }

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
        perform(sql) { stmt in
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
        }
    }

    func loadAllTokenUsage() -> [TokenUsageRecord] {
        // Columns are listed rather than `SELECT *` so the indices below stay valid
        // when a future migration adds a column in the middle of the table.
        let sql = """
            SELECT id, created_at, stage, model,
                   input_tokens, output_tokens, total_tokens,
                   cached_input_tokens, reasoning_tokens,
                   audio_input_tokens, audio_output_tokens, audio_seconds
            FROM token_usage ORDER BY created_at ASC
        """
        return query(sql) { stmt in
            guard let idStr = columnText(stmt, 0),
                  let id = UUID(uuidString: idStr),
                  let stageStr = columnText(stmt, 2),
                  let stage = UsageStage(rawValue: stageStr),
                  let model = columnText(stmt, 3) else { return nil }
            let usage = TokenUsage(
                inputTokens: Int(sqlite3_column_int(stmt, 4)),
                outputTokens: Int(sqlite3_column_int(stmt, 5)),
                totalTokens: Int(sqlite3_column_int(stmt, 6)),
                cachedInputTokens: Int(sqlite3_column_int(stmt, 7)),
                reasoningTokens: Int(sqlite3_column_int(stmt, 8)),
                audioInputTokens: Int(sqlite3_column_int(stmt, 9)),
                audioOutputTokens: Int(sqlite3_column_int(stmt, 10)),
                audioSeconds: columnOptionalDouble(stmt, 11)
            )
            return TokenUsageRecord(
                id: id,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                stage: stage,
                model: model,
                usage: usage
            )
        }
    }

    func clearTokenUsage() {
        execute("DELETE FROM token_usage")
    }

    // MARK: - Pipeline Runs (Stage Timing)

    func insertPipelineRun(_ report: PipelineRunReport) {
        let runID = report.id.uuidString
        inTransaction {
            let runSQL = """
                INSERT OR REPLACE INTO pipeline_run
                (id, started_at, ended_at, outcome, outcome_message, prompt_target, first_partial_ms)
                VALUES (?,?,?,?,?,?,?)
            """
            guard perform(runSQL, { stmt in
                sqlite3_bind_text(stmt, 1, runID, -1, SQLITE_TRANSIENT)
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
            }) else { return false }

            // Replace this run's stage rows rather than appending to them.
            guard perform("DELETE FROM stage_duration WHERE run_id = ?", { stmt in
                sqlite3_bind_text(stmt, 1, runID, -1, SQLITE_TRANSIENT)
            }) else { return false }

            let stageSQL = """
                INSERT INTO stage_duration (run_id, stage, started_at, ended_at, duration_ms, detail)
                VALUES (?,?,?,?,?,?)
            """
            for stage in report.stages {
                guard perform(stageSQL, { stmt in
                    sqlite3_bind_text(stmt, 1, runID, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, stage.stage.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(stmt, 3, stage.startedAt.timeIntervalSince1970)
                    sqlite3_bind_double(stmt, 4, stage.endedAt.timeIntervalSince1970)
                    sqlite3_bind_int(stmt, 5, Int32(stage.durationMs))
                    bindOptionalText(stmt, 6, stage.detail)
                }) else { return false }
            }
            return true
        }
    }

    func loadAllPipelineRuns() -> [PipelineRunReport] {
        let sql = """
            SELECT id, started_at, ended_at, outcome, outcome_message, prompt_target, first_partial_ms
            FROM pipeline_run ORDER BY started_at DESC
        """
        return query(sql) { stmt in
            guard let idStr = columnText(stmt, 0),
                  let id = UUID(uuidString: idStr),
                  let outcomeStr = columnText(stmt, 3),
                  let outcome = PipelineRunOutcome(rawValue: outcomeStr) else { return nil }
            return PipelineRunReport(
                id: id,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                endedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                outcome: outcome,
                outcomeMessage: columnText(stmt, 4),
                stages: loadStages(forRunID: idStr),
                promptTarget: columnText(stmt, 5),
                firstPartialMs: columnOptionalInt(stmt, 6)
            )
        }
    }

    func clearPipelineRuns() {
        inTransaction {
            execute("DELETE FROM stage_duration") && execute("DELETE FROM pipeline_run")
        }
    }

    private func loadStages(forRunID runID: String) -> [StageDuration] {
        // `duration_ms` is stored for external queries but recomputed by StageDuration
        // from the two timestamps, so it is not selected here.
        let sql = """
            SELECT stage, started_at, ended_at, detail
            FROM stage_duration WHERE run_id = ? ORDER BY started_at ASC
        """
        return query(sql) { stmt -> Void in
            sqlite3_bind_text(stmt, 1, runID, -1, SQLITE_TRANSIENT)
        } row: { stmt in
            guard let stageStr = columnText(stmt, 0),
                  let stage = PipelineStage(rawValue: stageStr) else { return nil }
            return StageDuration(
                stage: stage,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                endedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                detail: columnText(stmt, 3)
            )
        }
    }

    // MARK: - Recognition Prompts

    func loadRecognitionPrompts() -> [String] {
        query("SELECT word FROM recognition_prompt ORDER BY id ASC") { stmt in
            columnText(stmt, 0)
        }
    }

    func saveRecognitionPrompts(_ words: [String]) {
        // The delete and the inserts replace the whole list, so a failure part way
        // through must not leave the user with a truncated vocabulary.
        inTransaction {
            guard execute("DELETE FROM recognition_prompt") else { return false }
            let sql = "INSERT OR IGNORE INTO recognition_prompt (word) VALUES (?)"
            for word in words where !word.isEmpty {
                guard perform(sql, { stmt in
                    sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
                }) else { return false }
            }
            return true
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &message)
        guard status != SQLITE_OK else { return true }
        let detail = message.map { String(cString: $0) } ?? "status \(status)"
        sqlite3_free(message)
        Self.log.error("sqlite exec failed: \(detail, privacy: .public)")
        return false
    }

    /// Run `body` inside a transaction and roll back unless it reports success.
    ///
    /// `insertPipelineRun` used to BEGIN, ignore every prepare failure, and COMMIT
    /// regardless, so a run could be written with only some of its stages. If BEGIN
    /// itself failed the COMMIT then applied to whatever transaction was already open.
    @discardableResult
    private func inTransaction(_ body: () -> Bool) -> Bool {
        guard execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
        if body(), execute("COMMIT") { return true }
        execute("ROLLBACK")
        return false
    }

    /// Prepare, bind, step and finalize a single statement. Returns false if any step
    /// fails, so a caller inside `inTransaction` can roll back.
    @discardableResult
    private func perform(_ sql: String, _ bind: (OpaquePointer?) -> Void) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Self.log.error("sqlite prepare failed: \(Self.lastErrorMessage(self.db), privacy: .public)")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        let status = sqlite3_step(stmt)
        guard status == SQLITE_DONE || status == SQLITE_ROW else {
            Self.log.error("sqlite step failed: \(Self.lastErrorMessage(self.db), privacy: .public)")
            return false
        }
        return true
    }

    /// Prepare `sql`, step it to exhaustion and map each row. Rows the mapper rejects
    /// (unknown enum case, malformed UUID) are skipped rather than failing the read.
    private func query<T>(
        _ sql: String,
        bind: (OpaquePointer?) -> Void = { _ in },
        row: (OpaquePointer?) -> T?
    ) -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Self.log.error("sqlite prepare failed: \(Self.lastErrorMessage(self.db), privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        var results: [T] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let value = row(stmt) { results.append(value) }
            status = sqlite3_step(stmt)
        }
        if status != SQLITE_DONE {
            Self.log.error("sqlite step failed: \(Self.lastErrorMessage(self.db), privacy: .public)")
        }
        return results
    }

    private static func lastErrorMessage(_ db: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: message)
    }

    private static let log = Logger(
        subsystem: "app.vibevoice.oss.macos",
        category: "datastore"
    )

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func columnOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func columnOptionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(stmt, index))
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
