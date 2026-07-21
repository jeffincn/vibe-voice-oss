// Copyright © 2025 OnType
// Qwen3-ASR Tokenizer wrapper

import Foundation
import Tokenizers

/// Qwen3-ASR tokenizer wrapper
///
/// Uses swift-transformers AutoTokenizer for Qwen3 tokenization.
/// Handles special tokens for audio speech recognition.
public final class Qwen3ASRTokenizer {
    private let tokenizer: Tokenizer

    // Special token IDs
    public let audioTokenId: Int
    public let audioStartTokenId: Int
    public let audioEndTokenId: Int
    public let eosTokenIds: Set<Int>

    // Special token strings
    private let audioStartToken = "<|audio_start|>"
    private let audioEndToken = "<|audio_end|>"
    private let audioPadToken = "<|audio_pad|>"
    private let imStartToken = "<|im_start|>"
    private let imEndToken = "<|im_end|>"

    private init(
        tokenizer: Tokenizer,
        audioTokenId: Int,
        audioStartTokenId: Int,
        audioEndTokenId: Int
    ) {
        self.tokenizer = tokenizer
        self.audioTokenId = audioTokenId
        self.audioStartTokenId = audioStartTokenId
        self.audioEndTokenId = audioEndTokenId

        // Build EOS token set
        var eosIds = Set<Int>()
        // Standard Qwen3 EOS tokens
        eosIds.insert(151645) // <|im_end|>
        eosIds.insert(151643) // <|endoftext|>
        if let tokenizerEos = tokenizer.eosTokenId {
            eosIds.insert(tokenizerEos)
        }
        eosTokenIds = eosIds
    }

    /// Load tokenizer from model directory
    ///
    /// - Parameters:
    ///   - modelDirectory: Path to model directory
    ///   - config: Qwen3-ASR configuration
    /// - Returns: Initialized tokenizer
    public static func load(
        from modelDirectory: URL,
        config: Qwen3ASRConfig
    ) async throws -> Qwen3ASRTokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: modelDirectory)
        return Qwen3ASRTokenizer(
            tokenizer: tokenizer,
            audioTokenId: config.audioTokenId,
            audioStartTokenId: config.audioStartTokenId,
            audioEndTokenId: config.audioEndTokenId
        )
    }

    /// Encode text to token IDs
    public func encode(_ text: String) -> [Int] {
        tokenizer.encode(text: text)
    }

    /// Decode token IDs to text
    public func decode(_ tokens: [Int]) -> String {
        tokenizer.decode(tokens: tokens)
    }

    /// Check if token is an EOS token
    public func isEosToken(_ tokenId: Int) -> Bool {
        eosTokenIds.contains(tokenId)
    }

    /// Build prompt for transcription
    ///
    /// Format:
    /// ```
    /// <|im_start|>system
    /// <|im_end|>
    /// <|im_start|>user
    /// <|audio_start|><|audio_pad|>...<|audio_end|><|im_end|>
    /// <|im_start|>assistant
    /// language English<asr_text>
    /// ```
    ///
    /// - Parameters:
    ///   - numAudioTokens: Number of audio tokens (determines audio_pad count)
    ///   - language: Target language for transcription (omit/auto for detection)
    ///   - context: Optional system-prompt context for hotword biasing
    /// - Returns: Encoded prompt token IDs
    public func buildPrompt(
        numAudioTokens: Int,
        language: String? = "English",
        context: String? = nil
    ) -> [Int] {
        let audioTokens = String(repeating: audioPadToken, count: numAudioTokens)
        let languageLine: String
        if let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           language.lowercased() != "auto"
        {
            languageLine = "language \(language)<asr_text>"
        } else {
            languageLine = "<asr_text>"
        }
        let systemContext = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let systemLine = systemContext.isEmpty ? "" : "\(systemContext)\n"

        let prompt = """
            \(imStartToken)system
            \(systemLine)\(imEndToken)
            \(imStartToken)user
            \(audioStartToken)\(audioTokens)\(audioEndToken)\(imEndToken)
            \(imStartToken)assistant
            \(languageLine)
            """

        return encode(prompt)
    }

    /// Find audio token positions in token IDs
    ///
    /// - Parameter tokenIds: Array of token IDs
    /// - Returns: Range of audio token positions (indices to replace with audio features)
    public func findAudioTokenPositions(_ tokenIds: [Int]) -> Range<Int>? {
        var startIdx: Int?
        var endIdx: Int?

        for (i, tokenId) in tokenIds.enumerated() {
            if tokenId == audioStartTokenId, startIdx == nil {
                startIdx = i + 1 // Start after audio_start token
            }
            if tokenId == audioEndTokenId, endIdx == nil {
                endIdx = i // End before audio_end token
            }
        }

        if let start = startIdx, let end = endIdx, start < end {
            return start ..< end
        }
        return nil
    }

    /// Parse generated output into text + optional detected language.
    public func parseOutput(_ text: String) -> (text: String, language: String?) {
        var cleaned = text

        // Remove special tokens
        let specialTokens = [
            imStartToken, imEndToken,
            audioStartToken, audioEndToken, audioPadToken,
            "<|endoftext|>", "<asr_text>", "</asr_text>",
        ]
        for token in specialTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }

        var detectedLanguage: String?
        // Remove language prefix if present
        if cleaned.hasPrefix("language ") {
            if let range = cleaned.range(of: "\n") {
                let line = cleaned[..<range.lowerBound]
                detectedLanguage = line.replacingOccurrences(of: "language ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cleaned = String(cleaned[range.upperBound...])
            } else {
                detectedLanguage = cleaned.replacingOccurrences(of: "language ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cleaned = ""
            }
        }

        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), detectedLanguage)
    }

    /// Clean generated output text
    public func cleanOutput(_ text: String) -> String {
        parseOutput(text).text
    }
}
