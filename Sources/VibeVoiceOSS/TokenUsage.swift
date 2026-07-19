import Foundation

/// Provider-reported usage for one API request. Detail fields are subsets of the
/// corresponding input/output totals and must not be added to `totalTokens` again.
struct TokenUsage: Codable, Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var totalTokens = 0
    var cachedInputTokens = 0
    var reasoningTokens = 0
    var audioInputTokens = 0
    var audioOutputTokens = 0
    var audioSeconds: Double?

    var isEmpty: Bool {
        inputTokens == 0 && outputTokens == 0 && totalTokens == 0
            && cachedInputTokens == 0 && reasoningTokens == 0
            && audioInputTokens == 0 && audioOutputTokens == 0
            && audioSeconds == nil
    }

    mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens
        cachedInputTokens += other.cachedInputTokens
        reasoningTokens += other.reasoningTokens
        audioInputTokens += other.audioInputTokens
        audioOutputTokens += other.audioOutputTokens
        if let seconds = other.audioSeconds {
            audioSeconds = (audioSeconds ?? 0) + seconds
        }
    }

    /// Accepts OpenAI Responses/Chat usage, Realtime usage details, and Audio
    /// transcription usage (`type: tokens` or `type: duration`).
    static func parse(_ value: Any?) -> TokenUsage? {
        guard let json = value as? [String: Any] else { return nil }
        func int(_ keys: String...) -> Int {
            for key in keys {
                if let value = json[key] as? Int { return value }
                if let value = json[key] as? NSNumber { return value.intValue }
            }
            return 0
        }
        func nestedInt(_ containerKeys: [String], _ keys: [String]) -> Int {
            for containerKey in containerKeys {
                guard let detail = json[containerKey] as? [String: Any] else { continue }
                for key in keys {
                    if let value = detail[key] as? Int { return value }
                    if let value = detail[key] as? NSNumber { return value.intValue }
                }
            }
            return 0
        }

        let input = int("input_tokens", "prompt_tokens")
        let output = int("output_tokens", "completion_tokens")
        var usage = TokenUsage(
            inputTokens: input,
            outputTokens: output,
            totalTokens: int("total_tokens"),
            cachedInputTokens: nestedInt(
                ["input_tokens_details", "input_token_details", "prompt_tokens_details"],
                ["cached_tokens"]
            ),
            reasoningTokens: nestedInt(
                ["output_tokens_details", "completion_tokens_details"],
                ["reasoning_tokens"]
            ),
            audioInputTokens: int("input_audio_tokens") + nestedInt(
                ["input_tokens_details", "input_token_details", "prompt_tokens_details"],
                ["audio_tokens"]
            ),
            audioOutputTokens: int("output_audio_tokens") + nestedInt(
                ["output_tokens_details", "completion_tokens_details"],
                ["audio_tokens"]
            ),
            audioSeconds: (json["seconds"] as? NSNumber)?.doubleValue
        )
        if usage.totalTokens == 0 { usage.totalTokens = input + output }
        return usage.isEmpty ? nil : usage
    }
}

enum UsageStage: String, Codable, CaseIterable, Sendable {
    case transcription
    case structuring
    case translation
    case promptOptimization

    var label: String {
        switch self {
        case .transcription: "语音转写"
        case .structuring: "内容整理"
        case .translation: "翻译"
        case .promptOptimization: "Prompt 优化"
        }
    }
}

struct TokenUsageRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let stage: UsageStage
    let model: String
    let usage: TokenUsage
}

@MainActor
final class TokenUsageStore: ObservableObject {
    @Published private(set) var records: [TokenUsageRecord] = []
    private let maxRecords = 1_000
    private let store = DataStore.shared

    init(defaults: UserDefaults = .standard) {
        records = store.loadAllTokenUsage()

        // One-time migration from legacy UserDefaults / JSON.
        if records.isEmpty {
            let migrated = Self.migrateFromLegacy(defaults: defaults)
            if !migrated.isEmpty {
                for record in migrated { store.insertTokenUsage(record) }
                records = migrated
            }
        }
    }

    var total: TokenUsage {
        records.reduce(into: TokenUsage()) { $0.add($1.usage) }
    }

    func record(_ usage: TokenUsage, stage: UsageStage, model: String) {
        guard !usage.isEmpty else { return }
        let record = TokenUsageRecord(
            id: UUID(), createdAt: Date(), stage: stage, model: model, usage: usage
        )
        records.append(record)
        if records.count > maxRecords { records.removeFirst(records.count - maxRecords) }
        store.insertTokenUsage(record)
    }

    func clear() {
        records = []
        store.clearTokenUsage()
    }

    private static func migrateFromLegacy(defaults: UserDefaults) -> [TokenUsageRecord] {
        // Try JSON file first, then UserDefaults.
        let fileURL = PersistenceDirectory.url.appendingPathComponent("token_usage.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TokenUsageRecord].self, from: data) {
            try? FileManager.default.removeItem(at: fileURL)
            return decoded
        }
        if let data = defaults.data(forKey: "tokenUsageRecords.v1"),
           let decoded = try? JSONDecoder().decode([TokenUsageRecord].self, from: data) {
            defaults.removeObject(forKey: "tokenUsageRecords.v1")
            return decoded
        }
        return []
    }
}

/// Shared directory for persisting app data.
enum PersistenceDirectory {
    static let url: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("VibeVoiceOSS", isDirectory: true)
    }()

    static func ensureExists() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
