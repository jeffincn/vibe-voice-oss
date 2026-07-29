import Foundation

#if canImport(CoreML)
import CoreML
#endif

struct PredictionContext: Sendable, Equatable {
    let preedit: String
    let committedPrefix: String
    /// A bounded local window supplied by UITextDocumentProxy. It is kept
    /// in-memory and is never persisted or sent over the network.
    let documentContext: String
    let schema: RimeSchema
    let candidates: [RimeCandidate]
    let language: KeyboardLanguage

    init(preedit: String, committedPrefix: String = "", documentContext: String = "",
         schema: RimeSchema = RimeEngineFactory.selectedSchema,
         candidates: [RimeCandidate], language: KeyboardLanguage = .chinese) {
        self.preedit = preedit
        self.committedPrefix = committedPrefix
        self.documentContext = Self.boundContext(documentContext)
        self.schema = schema
        self.candidates = candidates
        self.language = language
    }

    private static func boundContext(_ value: String) -> String {
        // Keep inference bounded for the keyboard extension. Prefer the text
        // nearest the insertion point, which is the most useful dialogue turn.
        let scalars = Array(value)
        let limit = 240
        return String(scalars.count > limit ? scalars.suffix(limit) : scalars)
    }
}

protocol CandidateRanker: AnyObject {
    var status: CandidateRankerStatus { get }
    func rank(_ context: PredictionContext) async -> [RimeCandidate]
}

enum CandidateRankerStatus: Equatable, Sendable {
    case disabled
    case loading
    case ready(version: String)
    case unavailable(String)
}

/// Deterministic fallback used on all OS versions and whenever a model is not
/// installed. It preserves Rime's order and applies only local accepted-count
/// boosts, so it never changes the engine's meaning or privacy boundary.
final class PassthroughCandidateRanker: CandidateRanker {
    private let persistLearning: Bool
    private let stats = LocalCandidateStats()
    var status: CandidateRankerStatus { .disabled }

    init(persistLearning: Bool = true) {
        self.persistLearning = persistLearning
    }

    func rank(_ context: PredictionContext) async -> [RimeCandidate] {
        guard persistLearning else { return context.candidates }
        return context.candidates.sorted {
            stats.score(prefix: context.preedit, candidate: $0.text) >
                stats.score(prefix: context.preedit, candidate: $1.text)
        }
    }

    func record(_ candidate: RimeCandidate, context: PredictionContext) {
        guard persistLearning else { return }
        stats.record(prefix: context.preedit, candidate: candidate.text)
    }
}

/// Optional Core ML reranker. The model is deliberately treated as a scorer,
/// not a text generator: Rime remains the source of all candidates.
final class CoreMLCandidateRanker: CandidateRanker {
    /// Fixed-size, privacy-preserving sentence/candidate representation. The
    /// model never receives a transcript database or audio; it sees the whole
    /// active preedit and one Rime candidate at a time. Hashing keeps the
    /// keyboard extension small while allowing a downloaded model to learn
    /// phrase and context n-grams without changing the model interface.
    private static let featureCount = 128
    private let fallback: PassthroughCandidateRanker
    private(set) var status: CandidateRankerStatus = .loading
    private(set) var lastInferenceUsed = false
    #if canImport(CoreML)
    private var model: MLModel?
    private var inputName: String?
    private var outputName: String?
    #else
    private var model: AnyObject?
    #endif

    init(fallback: PassthroughCandidateRanker = PassthroughCandidateRanker(), modelURL: URL? = nil) {
        self.fallback = fallback
        #if canImport(CoreML)
        if let modelURL {
            do {
                model = try MLModel(contentsOf: modelURL)
                inputName = model?.modelDescription.inputDescriptionsByName.keys.sorted().first
                outputName = model?.modelDescription.outputDescriptionsByName.keys.sorted().first
                guard inputName != nil, outputName != nil else {
                    status = .unavailable("Candidate model has no input/output")
                    return
                }
                status = .ready(version: modelURL.deletingPathExtension().lastPathComponent)
            } catch {
                status = .unavailable(error.localizedDescription)
            }
        } else {
            status = .unavailable("No candidate ranker model installed")
        }
        #else
        status = .unavailable("Core ML is unavailable")
        #endif
    }

    func rank(_ context: PredictionContext) async -> [RimeCandidate] {
        lastInferenceUsed = false
        #if canImport(CoreML)
        guard let model, let inputName, let outputName else {
            return await fallback.rank(context)
        }
        var scored: [(candidate: RimeCandidate, score: Double, index: Int)] = []
        for (index, candidate) in context.candidates.enumerated() {
            guard let score = score(candidate: candidate, context: context, model: model,
                                    inputName: inputName, outputName: outputName) else {
                return await fallback.rank(context)
            }
            scored.append((candidate, score, index))
        }
        lastInferenceUsed = true
        return scored.sorted {
            if $0.score == $1.score { return $0.index < $1.index }
            return $0.score > $1.score
        }.map(\.candidate)
        #else
        return await fallback.rank(context)
        #endif
    }

    #if canImport(CoreML)
    private func score(candidate: RimeCandidate, context: PredictionContext, model: MLModel,
                       inputName: String, outputName: String) -> Double? {
        let values = Self.sentenceFeatures(candidate: candidate, context: context)
        guard let features = try? MLMultiArray(shape: [NSNumber(value: Self.featureCount)], dataType: .double) else { return nil }
        for (index, value) in values.enumerated() { features[index] = NSNumber(value: value) }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: features)
        ]),
        let result = try? model.prediction(from: provider),
        let value = result.featureValue(for: outputName) else { return nil }
        if value.type == .double { return value.doubleValue }
        if let array = value.multiArrayValue, array.count > 0 { return array[0].doubleValue }
        return nil
    }

    private static func sentenceFeatures(candidate: RimeCandidate, context: PredictionContext) -> [Double] {
        var values = Array(repeating: 0.0, count: featureCount)
        values[0] = min(max((candidate.rawWeight ?? 0) / 100_000, -10), 10)
        values[1] = Double(candidate.text.count) / 16.0
        values[2] = Double(context.preedit.count) / 64.0
        values[3] = candidate.text.count > 1 ? 1 : 0
        values[4] = candidate.source == nil ? 0 : 1

        // FNV-1a is stable across Swift/Python and intentionally not
        // cryptographic: this is only a compact feature index.
        func bucket(_ text: String) -> Int {
            var hash: UInt64 = 14695981039346656037
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            return 5 + Int(hash % UInt64(featureCount - 5))
        }
        let chars = Array(candidate.text)
        for character in chars { values[bucket("c1:\(character)")] += 1.0 }
        if chars.count > 1 {
            for index in 0..<(chars.count - 1) {
                values[bucket("c2:\(chars[index])\(chars[index + 1])")] += 1.0
            }
        }
        // Pair n-grams bind the candidate to the complete pinyin context,
        // preventing a generic high-frequency word from winning every phrase.
        let pair = "p:\(context.preedit)|d:\(context.documentContext)|c:\(candidate.text)"
        values[bucket("pair:\(pair)")] += 1.0
        let contextChars = Array(context.documentContext)
        for character in contextChars {
            values[bucket("d1:\(character)")] += 0.25
        }
        if contextChars.count > 1 {
            for index in 0..<(contextChars.count - 1) {
                values[bucket("d2:\(contextChars[index])\(contextChars[index + 1])")] += 0.5
            }
        }
        return values
    }
    #endif

    func record(_ candidate: RimeCandidate, context: PredictionContext) {
        fallback.record(candidate, context: context)
    }
}

enum CandidateRankerFactory {
    static func make() -> CandidateRanker {
        let fallback = PassthroughCandidateRanker()
        return CoreMLCandidateRanker(fallback: fallback, modelURL: modelURL())
    }

    static func modelURL() -> URL? {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: RimeEngineFactory.appGroupIdentifier
        ) {
            let url = container.appendingPathComponent("Models/CandidateRanker/downloaded/VibeCandidateRanker.mlmodelc")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // The first model ships as a compiled Core ML resource so the keyboard
        // works immediately offline. Downloaded models take precedence above.
        let bundles = [Bundle.main, Bundle(for: LibrimeEngine.self)]
        for bundle in bundles {
            if let url = bundle.url(
            forResource: "VibeCandidateRanker",
            withExtension: "mlmodelc",
            subdirectory: "CandidateRanker"
            ) ?? bundle.url(forResource: "VibeCandidateRanker", withExtension: "mlmodelc") {
                return url
            }
        }
        return nil
    }
}

private final class LocalCandidateStats {
    private let defaults = UserDefaults(suiteName: RimeEngineFactory.appGroupIdentifier)
    private let lock = NSLock()

    private func key(prefix: String, candidate: String) -> String {
        // The key is only an opaque counter identifier; no raw transcript is
        // stored as a document or synchronized outside the App Group.
        let payload = Data("\(prefix)\u{001f}\(candidate)".utf8).base64EncodedString()
        return "prediction.accepted.\(payload)"
    }

    func record(prefix: String, candidate: String) {
        lock.lock(); defer { lock.unlock() }
        let counterKey = key(prefix: prefix, candidate: candidate)
        defaults?.set((defaults?.integer(forKey: counterKey) ?? 0) + 1, forKey: counterKey)
    }

    func score(prefix: String, candidate: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return defaults?.integer(forKey: key(prefix: prefix, candidate: candidate)) ?? 0
    }
}
