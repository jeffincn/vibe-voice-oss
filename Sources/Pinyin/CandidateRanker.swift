import Foundation

#if canImport(CoreML)
import CoreML
#endif

public struct RimeCandidate: Equatable, Sendable {
    public let text: String
    public let comment: String?
    /// Position librime gave the candidate on the current page. Selection has to
    /// travel back through this index because reranking changes display order.
    public let engineIndex: Int
    /// librime's C API exposes no dictionary weight, so this stays nil outside
    /// tests and the scorer reads a missing weight as zero.
    public let rawWeight: Double?
    public let source: String?

    public init(
        text: String,
        comment: String? = nil,
        engineIndex: Int = 0,
        rawWeight: Double? = nil,
        source: String? = nil
    ) {
        self.text = text
        self.comment = comment
        self.engineIndex = engineIndex
        self.rawWeight = rawWeight
        self.source = source
    }
}

public struct PredictionContext: Sendable, Equatable {
    public let preedit: String
    public let committedPrefix: String
    /// A bounded window of the text before the insertion point, read from the
    /// focused client and/or the in-memory session buffer. It is kept in memory
    /// and is never persisted or sent over the network.
    public let documentContext: String
    public let candidates: [RimeCandidate]

    public static let contextCharacterLimit = 512

    public init(
        preedit: String,
        committedPrefix: String = "",
        documentContext: String = "",
        candidates: [RimeCandidate]
    ) {
        self.preedit = preedit
        self.committedPrefix = committedPrefix
        self.documentContext = Self.boundContext(documentContext)
        self.candidates = candidates
    }

    public static func boundContext(_ value: String) -> String {
        // Prefer the text nearest the insertion point, which is the most useful
        // dialogue turn, and keep inference bounded for a per-keystroke path.
        let characters = Array(value)
        let limit = contextCharacterLimit
        return String(characters.count > limit ? characters.suffix(limit) : characters)
    }

    /// Merge client preceding text with the IME session buffer. Prefer the
    /// document when it is present; otherwise fall back to session history so
    /// multi-turn dialogue still has context in empty windows.
    public static func mergeContext(preceding: String, session: String) -> String {
        let preceding = preceding.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = session.trimmingCharacters(in: .whitespacesAndNewlines)
        if preceding.isEmpty { return boundContext(session) }
        if session.isEmpty { return boundContext(preceding) }
        if preceding.hasSuffix(session) || session.hasSuffix(preceding) {
            return boundContext(preceding.count >= session.count ? preceding : session)
        }
        // Overlap-trim: if the session already ends with the start of preceding,
        // avoid duplicating the shared tail.
        let maxOverlap = min(session.count, preceding.count, 64)
        var overlap = 0
        let sessionChars = Array(session)
        let precedingChars = Array(preceding)
        for length in stride(from: maxOverlap, through: 1, by: -1) {
            if sessionChars.suffix(length) == precedingChars.prefix(length) {
                overlap = length
                break
            }
        }
        let combined = String(sessionChars.dropLast(overlap)) + preceding
        return boundContext(combined)
    }

    /// Leading confirmed CJK / non-Latin segments that librime left in the
    /// preedit after a partial select (e.g. "真实nei rong" → "真实").
    public static func committedPrefix(fromPreedit preedit: String) -> String {
        var prefix = ""
        for character in preedit {
            if character.isASCII, character.isLetter || character == "'" || character == " " {
                break
            }
            if character.isASCII, character.isNumber {
                break
            }
            prefix.append(character)
        }
        return prefix
    }
}

public enum CandidateRankerStatus: Equatable, Sendable {
    case disabled
    case loading
    case ready(version: String)
    case unavailable(String)
}

/// Ranking runs inside `candidates(_:)` on the input thread, so it is
/// synchronous: the scorer is a compact MLP and an async hop would cost more
/// than the inference it defers.
public protocol CandidateRanker: AnyObject {
    var status: CandidateRankerStatus { get }
    func rank(_ context: PredictionContext) -> [RimeCandidate]
    func record(_ candidate: RimeCandidate, context: PredictionContext)
}

/// Deterministic fallback used whenever a model is not installed. It preserves
/// Rime's order and applies only local accepted-count boosts, so it never
/// changes the engine's meaning or the privacy boundary.
public final class PassthroughCandidateRanker: CandidateRanker {
    private let persistLearning: Bool
    private let stats: LocalCandidateStats
    public var status: CandidateRankerStatus { .disabled }

    public init(persistLearning: Bool = true, defaults: UserDefaults? = nil) {
        self.persistLearning = persistLearning
        self.stats = LocalCandidateStats(defaults: defaults)
    }

    public func rank(_ context: PredictionContext) -> [RimeCandidate] {
        guard persistLearning else { return context.candidates }
        // Swift's sort is not stable, so candidates the user has never accepted
        // would otherwise be shuffled out of Rime's order for no reason.
        return context.candidates
            .enumerated()
            .sorted { left, right in
                let leftScore = stats.score(prefix: context.preedit, candidate: left.element.text)
                let rightScore = stats.score(prefix: context.preedit, candidate: right.element.text)
                if leftScore == rightScore { return left.offset < right.offset }
                return leftScore > rightScore
            }
            .map(\.element)
    }

    public func record(_ candidate: RimeCandidate, context: PredictionContext) {
        guard persistLearning else { return }
        stats.record(prefix: context.preedit, candidate: candidate.text)
    }
}

/// Optional Core ML reranker. The model is deliberately treated as a scorer,
/// not a text generator: Rime remains the source of all candidate text.
public final class CoreMLCandidateRanker: CandidateRanker {
    /// Fixed-size, privacy-preserving sentence/candidate representation. The
    /// model never receives a transcript database or audio; it sees the whole
    /// active preedit, committed prefix, document/session context, and one
    /// Rime candidate at a time.
    public static let featureCount = 256
    /// How far the score may move a candidate, in list positions. Rime's own
    /// order already encodes dictionary weights that its C API does not expose,
    /// so a weakly trained scorer must be able to adjust that order, not
    /// replace it.
    private let maxRankShift: Double
    private let fallback: PassthroughCandidateRanker
    public private(set) var status: CandidateRankerStatus = .loading
    public private(set) var lastInferenceUsed = false
    #if canImport(CoreML)
    private var model: MLModel?
    private var inputName: String?
    private var outputName: String?
    #endif

    public init(
        fallback: PassthroughCandidateRanker = PassthroughCandidateRanker(),
        modelURL: URL?,
        maxRankShift: Double = 4
    ) {
        self.fallback = fallback
        self.maxRankShift = maxRankShift
        #if canImport(CoreML)
        guard let modelURL else {
            status = .unavailable("No candidate ranker model installed")
            return
        }
        do {
            let loaded = try MLModel(contentsOf: modelURL)
            guard let input = loaded.modelDescription.inputDescriptionsByName.keys.sorted().first,
                  let output = loaded.modelDescription.outputDescriptionsByName.keys.sorted().first else {
                status = .unavailable("Candidate model has no input/output")
                return
            }
            model = loaded
            inputName = input
            outputName = output
            status = .ready(version: modelURL.deletingPathExtension().lastPathComponent)
        } catch {
            status = .unavailable(error.localizedDescription)
        }
        #else
        status = .unavailable("Core ML is unavailable")
        #endif
    }

    public func rank(_ context: PredictionContext) -> [RimeCandidate] {
        lastInferenceUsed = false
        #if canImport(CoreML)
        guard let model, let inputName, let outputName, context.candidates.count > 1 else {
            return fallback.rank(context)
        }
        var scores: [Double] = []
        scores.reserveCapacity(context.candidates.count)
        for candidate in context.candidates {
            guard let score = score(
                candidate: candidate,
                context: context,
                model: model,
                inputName: inputName,
                outputName: outputName
            ) else {
                return fallback.rank(context)
            }
            scores.append(score)
        }
        lastInferenceUsed = true
        return reorder(context.candidates, scores: scores)
        #else
        return fallback.rank(context)
        #endif
    }

    /// Normalising per page bounds the shift whatever scale the model emits, so
    /// retraining cannot silently turn a reranker into a reshuffler.
    private func reorder(_ candidates: [RimeCandidate], scores: [Double]) -> [RimeCandidate] {
        let lowest = scores.min() ?? 0
        let span = (scores.max() ?? 0) - lowest
        return candidates
            .indices
            .sorted { left, right in
                let leftRank = Double(left) - shift(scores[left], lowest: lowest, span: span)
                let rightRank = Double(right) - shift(scores[right], lowest: lowest, span: span)
                if leftRank == rightRank { return left < right }
                return leftRank < rightRank
            }
            .map { candidates[$0] }
    }

    private func shift(_ score: Double, lowest: Double, span: Double) -> Double {
        guard span > 0 else { return 0 }
        return maxRankShift * (score - lowest) / span
    }

    #if canImport(CoreML)
    private func score(
        candidate: RimeCandidate,
        context: PredictionContext,
        model: MLModel,
        inputName: String,
        outputName: String
    ) -> Double? {
        let values = Self.sentenceFeatures(candidate: candidate, context: context)
        guard let features = try? MLMultiArray(
            shape: [NSNumber(value: Self.featureCount)],
            dataType: .double
        ) else { return nil }
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
    #endif

    public static func sentenceFeatures(candidate: RimeCandidate, context: PredictionContext) -> [Double] {
        var values = Array(repeating: 0.0, count: featureCount)
        // Dense hand-crafted slots (indices 0–15) stay unhashed so the MLP can
        // learn length / continuity priors without colliding with n-grams.
        values[0] = min(max((candidate.rawWeight ?? 0) / 100_000, -10), 10)
        values[1] = Double(candidate.text.count) / 16.0
        values[2] = Double(context.preedit.count) / 64.0
        values[3] = candidate.text.count > 1 ? 1 : 0
        values[4] = candidate.source == nil ? 0 : 1
        values[5] = Double(context.committedPrefix.count) / 16.0
        values[6] = Double(context.documentContext.count) / Double(PredictionContext.contextCharacterLimit)
        values[7] = min(Double(candidate.text.count), 8.0) / 8.0 // phrase-length reward
        values[8] = context.committedPrefix.isEmpty ? 0 : 1
        values[9] = context.documentContext.isEmpty ? 0 : 1
        // Dense slots 10–13: mixed-reasoning markers (shape stays 256-d).
        let source = candidate.source ?? ""
        let hasLatin = candidate.text.contains { $0.isASCII && $0.isLetter }
        values[10] = (source == ReasoningCandidate.source && hasLatin) ? 1 : 0  // proper/english-ish
        values[11] = hasLatin ? 1 : 0
        values[12] = (source == ReasoningCandidate.source || source == PinyinTypoCorrector.typoFixSource) ? 1 : 0
        values[13] = min(Double(candidate.text.count), 32) / 32.0  // proxy for segmentation span

        let chars = Array(candidate.text)
        for character in chars { values[bucket("c1:\(character)")] += 1.0 }
        if chars.count > 1 {
            for index in 0..<(chars.count - 1) {
                values[bucket("c2:\(chars[index])\(chars[index + 1])")] += 1.0
            }
        }

        let prefixChars = Array(context.committedPrefix)
        for character in prefixChars { values[bucket("p1:\(character)")] += 1.0 }
        if prefixChars.count > 1 {
            for index in 0..<(prefixChars.count - 1) {
                values[bucket("p2:\(prefixChars[index])\(prefixChars[index + 1])")] += 1.0
            }
        }
        if let lastPrefix = prefixChars.last, let firstCandidate = chars.first {
            values[bucket("pc:\(lastPrefix)\(firstCandidate)")] += 1.5
        }

        let contextChars = Array(context.documentContext)
        for character in contextChars {
            values[bucket("d1:\(character)")] += 0.25
        }
        if contextChars.count > 1 {
            for index in 0..<(contextChars.count - 1) {
                values[bucket("d2:\(contextChars[index])\(contextChars[index + 1])")] += 0.5
            }
        }
        // Cross-boundary bigrams bind the candidate to the dialogue tail.
        if let lastContext = contextChars.last, let firstCandidate = chars.first {
            values[bucket("dc:\(lastContext)\(firstCandidate)")] += 2.0
        }
        if contextChars.count >= 2, chars.count >= 1 {
            let tail = "\(contextChars[contextChars.count - 2])\(contextChars[contextChars.count - 1])"
            values[bucket("d2c:\(tail)\(chars[0])")] += 1.5
        }

        let pair = "p:\(context.preedit)|f:\(context.committedPrefix)|d:\(context.documentContext)|c:\(candidate.text)"
        values[bucket("pair:\(pair)")] += 1.0
        values[bucket("pair_short:p:\(context.preedit)|c:\(candidate.text)")] += 0.75
        values[bucket("pair_ctx:d:\(String(contextChars.suffix(24)))|c:\(candidate.text)")] += 1.25
        return values
    }

    /// FNV-1a is stable across Swift and the Python trainer and intentionally
    /// not cryptographic: this is only a compact feature index.
    private static func bucket(_ text: String) -> Int {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        // Reserve 0–15 for dense slots.
        return 16 + Int(hash % UInt64(featureCount - 16))
    }

    public func record(_ candidate: RimeCandidate, context: PredictionContext) {
        fallback.record(candidate, context: context)
    }
}

public enum CandidateRankerFactory {
    public static let defaultsSuiteName = "app.vibevoice.oss.shared"

    public static func make(persistLearning: Bool = true) -> CandidateRanker {
        let fallback = PassthroughCandidateRanker(persistLearning: persistLearning)
        guard let url = modelURL() else { return fallback }
        let ranker = CoreMLCandidateRanker(fallback: fallback, modelURL: url)
        if case .ready = ranker.status { return ranker }
        return fallback
    }

    /// A model dropped into Application Support wins, so a retrained scorer can
    /// be tried without reinstalling the input method. The bundled copy keeps
    /// the input method working offline out of the box.
    public static func modelURL(bundle: Bundle = .main) -> URL? {
        let downloaded = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                "VibeVoiceOSS/Models/CandidateRanker/VibeCandidateRanker.mlmodelc",
                isDirectory: true
            )
        if FileManager.default.fileExists(atPath: downloaded.path) { return downloaded }
        return bundle.url(
            forResource: "VibeCandidateRanker",
            withExtension: "mlmodelc",
            subdirectory: "CandidateRanker"
        ) ?? bundle.url(forResource: "VibeCandidateRanker", withExtension: "mlmodelc")
    }
}

/// Counts how often the user picked a candidate for a given pinyin prefix. The
/// key is an opaque identifier, so no readable transcript is written to disk.
final class LocalCandidateStats {
    private let defaults: UserDefaults?
    private let lock = NSLock()

    init(defaults: UserDefaults?) {
        self.defaults = defaults ?? UserDefaults(suiteName: CandidateRankerFactory.defaultsSuiteName)
    }

    private func key(prefix: String, candidate: String) -> String {
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
