// Copyright © 2025 OnType
// Qwen3-ASR Speech-to-Text interface
//
// ARCHITECTURE NOTES:
// This is the main entry point for Qwen3-ASR transcription. Key design decisions:
//
// 1. Actor-based concurrency: `Qwen3ASTSST` is an actor to ensure thread-safe
//    access to model state during concurrent transcriptions.
//
// 2. Performance-critical paths:
//    - Model loading: ~3-5s (one-time cost)
//    - Warmup: ~3-5s (eliminates JIT cold-start penalty, saving 5+ seconds on first request)
//    - Transcription: Targets <0.5x RTF (2x+ real-time speed)
//
// 3. PITFALL - Metal JIT Compilation:
//    MLX compiles Metal shaders at runtime. The FIRST transcription after app launch
//    incurs a ~5s JIT compilation overhead. ALWAYS call `warmup()` or use
//    `loadWithWarmup(from:)` to pre-compile shaders before real transcriptions.
//    System shader caches help subsequent app launches but are not 100% reliable.
//
// 4. PITFALL - Concurrency escape hatches:
//    Keep the model/tokenizer actor-isolated. Avoid exposing them via `nonisolated(unsafe)`
//    (or other shared mutable paths) unless you have a very clear need and have verified
//    MLX/MLXLMCommon thread-safety for the specific access pattern.

import Foundation
import MLX
import MLXLMCommon
import MLXNN

/// Transcription result containing text and performance metrics
public struct TranscriptionResult: Sendable {
    /// Transcribed text (cleaned of special tokens)
    public let text: String
    /// Detected or requested language (if available)
    public let language: String?
    /// Total processing time in seconds (mel + encode + generate)
    public let processingTime: Double
    /// Input audio duration in seconds
    public let audioDuration: Double

    /// Real-time factor: processingTime / audioDuration
    /// Values < 1.0 mean faster than real-time
    public var rtf: Double { processingTime / audioDuration }

    /// Speed multiplier: audioDuration / processingTime
    /// Values > 1.0 mean faster than real-time (e.g., 10x = 10 seconds of audio per second)
    public var speedMultiplier: Double { audioDuration / processingTime }
}

/// Actor wrapper for Qwen3-ASR model providing thread-safe transcription
///
/// ## Usage
/// ```swift
/// // Recommended: Load with warmup for optimal first-request performance
/// let stt = try await Qwen3ASRSTT.loadWithWarmup(from: modelDirectory)
///
/// // Transcribe audio
/// let result = try await stt.transcribe(file: audioURL)
/// print("Text: \(result.text)")
/// print("Speed: \(result.speedMultiplier)x real-time")
/// ```
///
	/// ## Thread Safety
	/// This actor ensures safe concurrent access. The model and tokenizer are
	/// actor-isolated to prevent accidental concurrent forward passes.
public actor Qwen3ASRSTT {
    let model: Qwen3ASRModel
    let tokenizer: Qwen3ASRTokenizer

    /// Model directory (for debugging/logging)
    public let modelDirectory: URL

    private init(model: Qwen3ASRModel, tokenizer: Qwen3ASRTokenizer, modelDirectory: URL) {
        self.model = model
        self.tokenizer = tokenizer
        self.modelDirectory = modelDirectory
    }

    private static func ensureMLXRuntimeReady() throws {
        do {
            try withError {
                // Probe both streams while the MLX error handler is active.
                // If GPU/Metal initialization fails, MLX otherwise degrades into
                // a later "expected a non-empty mlx_stream" error.
                _ = Stream(.gpu)
                _ = Stream(.cpu)
            }
        } catch {
            throw Qwen3ASRError.modelLoadFailed(
                "MLX runtime init failed: \(error.localizedDescription)"
            )
        }
    }

    private static func loadWeights(at weightsPath: URL) throws -> [String: MLXArray] {
        do {
            return try MLX.loadArrays(url: weightsPath)
        } catch {
            let message = error.localizedDescription
            if message.contains("expected a non-empty mlx_stream") {
                throw Qwen3ASRError.modelLoadFailed(
                    "MLX stream init failed while loading weights. " +
                        "This usually means Metal runtime initialization failed or metallib is incompatible. " +
                        "Original error: \(message)"
                )
            }
            throw Qwen3ASRError.modelLoadFailed("Failed to load weights: \(message)")
        }
    }

    /// Load Qwen3-ASR from a local directory
    ///
    /// This method loads the model WITHOUT warmup. The first transcription will incur
    /// JIT compilation overhead (~5s). For production use, prefer `loadWithWarmup(from:)`.
    ///
    /// - Parameter directory: Path to model directory containing:
    ///   - `config.json`: Model configuration
    ///   - `model.safetensors`: Model weights (quantized or full precision)
    ///   - `vocab.json` + `merges.txt`: BPE tokenizer files
    /// - Returns: Initialized Qwen3ASRSTT instance (not warmed up)
    /// - Throws: `Qwen3ASRError.modelLoadFailed` if files are missing or corrupt
    public static func load(from directory: URL) async throws -> Qwen3ASRSTT {
        // Load config
        let config = try Qwen3ASRConfig.load(from: directory)

        // Many MLX failures are surfaced via a global error handler that defaults to `fatalError`.
        // Convert those into Swift `throws` so the app can surface a HUD error instead of crashing.
        return try await withError {
            try Self.ensureMLXRuntimeReady()

            // Create model architecture (weights not loaded yet)
            let model = Qwen3ASRModel(config: config)

            // Load weights from safetensors
            let weightsPath = directory.appendingPathComponent("model.safetensors")
            guard FileManager.default.fileExists(atPath: weightsPath.path) else {
                throw Qwen3ASRError.modelLoadFailed("Weights file not found at \(weightsPath.path)")
            }

            let weights = try Self.loadWeights(at: weightsPath)
            let sanitized = Qwen3ASRModel.sanitize(weights: weights)

            // PITFALL: Quantized models require special handling
            // If weights contain ".scales" keys, the model was saved in quantized format.
            // We must configure matching quantization BEFORE loading weights.
            let isQuantized = sanitized.keys.contains { $0.contains(".scales") }
            if isQuantized {
                let q = config.quantizationConfig
                let groupSize = q?.groupSize ?? 64
                let bits = q?.bits ?? 4
                let mode = Self.mapQuantizationMode(q?.mode)

                // Dynamic quantization: only quantize layers that have .scales in weights.
                quantize(model: model) { path, _ in
                    sanitized["\(path).scales"] != nil ? (groupSize, bits, mode) : nil
                }
            }

            // Load weights into model
            // .noUnusedKeys ensures all weights are used (catches config mismatches)
            try model.update(parameters: ModuleParameters.unflattened(sanitized), verify: .noUnusedKeys)

            // Set to eval mode (disables dropout, batchnorm training behavior)
            model.train(false)

            // Force evaluation to ensure weights are on GPU
            // PITFALL: Without this, first inference triggers weight transfer + JIT
            eval(model)

            // Load BPE tokenizer
            let tokenizer = try await Qwen3ASRTokenizer.load(from: directory, config: config)

            return Qwen3ASRSTT(model: model, tokenizer: tokenizer, modelDirectory: directory)
        }
    }

    /// Load Qwen3-ASR with automatic warmup for optimal first-request performance
    ///
    /// **Recommended for production use.** This method loads the model and performs
    /// warmup transcriptions to pre-compile Metal shaders. The first real transcription
    /// will be fast (~2-3x real-time) instead of slow (~0.5x real-time).
    ///
    /// Total initialization time: ~6-10 seconds (load: 3-5s + warmup: 3-5s)
    ///
    /// - Parameter directory: Path to model directory
    /// - Returns: Warmed-up Qwen3ASRSTT instance ready for fast transcription
    public static func loadWithWarmup(from directory: URL) async throws -> Qwen3ASRSTT {
        let stt = try await load(from: directory)
        try await stt.warmup()
        return stt
    }

    // MARK: - Warmup

    /// Warmup the model by running dummy transcriptions
    ///
    /// ## Why Warmup is Necessary
    /// MLX compiles Metal compute kernels on first use (JIT). Without warmup:
    /// - First transcription: ~5-8s for 8s audio (~0.5x real-time)
    /// - Subsequent transcriptions: ~0.8s for 8s audio (~10x real-time)
    ///
    /// With warmup:
    /// - All transcriptions: ~0.8s for 8s audio (~10x real-time)
    ///
    /// ## What Gets Compiled
    /// - Mel spectrogram FFT kernels
    /// - Audio encoder attention/MLP kernels
    /// - Text decoder attention/MLP kernels (for different sequence lengths)
    /// - Quantized matmul kernels (if using quantized model)
    ///
    /// ## When to Call
    /// - After `load(from:)` if not using `loadWithWarmup(from:)`
    /// - Do NOT call multiple times (no benefit, wastes resources)
    public func warmup() async throws {
        // PITFALL: Use noise, not silence!
        // Silence produces near-zero mel values, which may not exercise all kernel paths.
        // Low-amplitude noise ensures diverse computations.
        //
        // Use 8s of audio so the batched Conv2d encoder processes ~8 chunks,
        // exercising realistic batch sizes. With only 2s (~2 chunks) the first
        // real transcription would still trigger Metal pipeline state compilation
        // for larger batch dimensions.
        let warmupDuration = 8.0
        let sampleCount = Int(Double(Qwen3ASRAudio.sampleRate) * warmupDuration)
        var warmupAudio = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            warmupAudio[i] = Float.random(in: -0.01...0.01)
        }

        // First run: compile all Metal kernels (mel, encoder, prefill, decode).
        // Use temperature=1.0 to force token generation even on noise input —
        // with greedy decoding the model emits EOS immediately (0 tokens),
        // leaving the autoregressive decode loop kernels uncompiled.
        _ = try transcribe(audio: warmupAudio, maxTokens: 32, temperature: 1.0)

        // Second run: already compiled, validates fast path at realistic scale.
        _ = try transcribe(audio: warmupAudio, maxTokens: 8)

        // Clear memory cache but keep shader cache
        // The shader cache persists, giving us fast subsequent inference
        MLX.Memory.clearCache()
    }

    /// Flush MLX's internal Metal buffer pool so freed model memory is returned to the OS.
    ///
    /// Call after dropping all references to a `Qwen3ASRSTT` instance (e.g. cache eviction)
    /// to ensure the resident memory actually decreases.  Without this, MLX keeps
    /// deallocated Metal buffers in a reuse pool indefinitely.
    public static func flushMemoryPool() {
        MLX.Memory.clearCache()
    }

    /// Lightweight keep-alive to touch the inference path and avoid deep idle paging stalls.
    public func keepAlive() async throws {
        let sampleCount = max(Qwen3ASRAudio.nFft, 800)
        let silence = [Float](repeating: 0, count: sampleCount)
        _ = try transcribe(audio: silence, maxTokens: 8)
    }

    // MARK: - Transcription

    /// Transcribe audio samples to text
    ///
    /// ## Processing Pipeline
    /// 1. **Mel spectrogram** (~50ms): Convert waveform to 128-bin log-mel features
    /// 2. **Audio encoding** (~200ms): Encode mel features with Whisper-style encoder
    /// 3. **Token generation** (~500ms): Autoregressive decoding with KV cache
    ///
    /// ## Performance Characteristics (after warmup, 8s audio)
    /// - Device dependent (CPU/GPU, model size, quantization).
    ///
    /// - Parameters:
    ///   - audio: Audio samples at 16kHz as Float array
    ///   - language: Optional language hint (omit/auto for detection)
    ///   - context: Optional system-prompt context for hotword biasing
    ///   - maxTokens: Maximum tokens to generate (default 4096)
    ///   - temperature: Sampling temperature (0.0 = greedy, >0 = stochastic)
    /// - Returns: Transcription result with text and timing metrics
    public func transcribe(
        audio: [Float],
        language: String? = nil,
        context: String? = nil,
        maxTokens: Int = 4096,
        temperature: Float = 0.0
    ) throws -> TranscriptionResult {
        // Audio shorter than one FFT window (400 samples = 25ms) cannot produce a valid
        // spectrogram and would crash in reflectPad with an invalid range.  Return empty.
        if audio.count < Qwen3ASRAudio.nFft {
            return TranscriptionResult(
                text: "",
                language: language,
                processingTime: 0,
                audioDuration: Double(audio.count) / Double(Qwen3ASRAudio.sampleRate)
            )
        }

        // Convert MLX errors into Swift `throws` (prevents process abort via MLX fatalError handler).
        return try withError {
            let startTime = CFAbsoluteTimeGetCurrent()
            let audioDuration = Double(audio.count) / Double(Qwen3ASRAudio.sampleRate)
            // Safety: Cap generation length based on audio duration to avoid pathological runs
            // where the model never emits EOS and we end up generating thousands of tokens.
            // Empirically, ASR outputs are far below ~20 tokens/sec, so this is a conservative guardrail.
            let durationBasedTokenCap = Int(ceil(audioDuration * 20.0)) + 64
            let effectiveMaxTokens = max(1, min(maxTokens, durationBasedTokenCap))

            // Convert to MLXArray
            let audioArray = MLXArray(audio)

            // ─────────────────────────────────────────────────────────────────────
            // Phase 1: Mel Spectrogram
            // Uses pre-computed Hann window and mel filterbank for efficiency
            // ─────────────────────────────────────────────────────────────────────
            let melSpec = logMelSpectrogram(audio: audioArray)
            // Transpose from (frames, mels) to (mels, frames) for model input
            let melSpecTransposed = melSpec.T
            // Add batch dimension: (mels, frames) -> (1, mels, frames)
            let inputFeatures = melSpecTransposed.expandedDimensions(axis: 0)
            let featureAttentionMask = MLXArray(
                Array(repeating: Int32(1), count: inputFeatures.shape[2])
            ).expandedDimensions(axis: 0)
            eval(inputFeatures)  // Force computation before timing

            // ─────────────────────────────────────────────────────────────────────
            // Phase 2: Audio Encoding
            // Whisper-style encoder: Conv -> Transformer -> Linear projection
            // ─────────────────────────────────────────────────────────────────────
            // Audio encoder now returns 2D (seqLen, outputDim) — no batch dim to remove
            let audioFeatures = model.getAudioFeatures(
                inputFeatures: inputFeatures,
                featureAttentionMask: featureAttentionMask
            )
            eval(audioFeatures)

            // ─────────────────────────────────────────────────────────────────────
            // Phase 3: Build Prompt
            // Format: <|im_start|>system<|im_end|><|im_start|>user<audio>Audio<|audio|>...<|im_start|>assistant
            // ─────────────────────────────────────────────────────────────────────
            // Keep prompt token count aligned with encoder output length formula.
            // If there is any mismatch, trust actual encoder output to avoid repeating/truncating features.
            let expectedAudioTokens = getAudioEncoderOutputLengths(
                MLXArray([Int32(inputFeatures.shape[2])])
            ).item(Int.self)
            let numAudioTokens = expectedAudioTokens == audioFeatures.shape[0]
                ? expectedAudioTokens
                : audioFeatures.shape[0]
            let promptTokenIds = tokenizer.buildPrompt(
                numAudioTokens: numAudioTokens,
                language: language,
                context: context
            )
            let inputIds = MLXArray(promptTokenIds.map { Int32($0) }).expandedDimensions(axis: 0)
            // Replace audio placeholder tokens with actual audio features
            let inputEmbeds = model.buildInputsEmbeds(inputIds: inputIds, audioFeatures: audioFeatures)

            // ─────────────────────────────────────────────────────────────────────
            // Phase 4: Token Generation with Double-Buffering
            //
            // PERFORMANCE OPTIMIZATION: Double-buffering pattern
            // We overlap GPU computation with CPU work by:
            // 1. Start next forward pass BEFORE extracting current token (asyncEval)
            // 2. Extract token ID (item() triggers GPU sync) while GPU computes next logits
            //
            // Without this: CPU waits for GPU after each token -> serial execution
            // With this: CPU extracts token N while GPU computes token N+1 -> pipelined
            // ─────────────────────────────────────────────────────────────────────
            var generatedTokens: [Int] = []
            generatedTokens.reserveCapacity(256)

            // Prefill: Process entire prompt, build KV cache
            // Uses .causal mask mode (symbolic mask, no memory allocation)
            var (logits, cache) = model(
                inputIds: inputIds,
                inputEmbeddings: inputEmbeds,
                cache: nil
            )
            asyncEval(logits, cache)  // Materialize logits + KV cache without blocking

            // Autoregressive generation with pipelining
            var repetitionCount = 0
            var lastToken = -1
            let maxRepetition = 10  // Stop if same token repeats 10 times (degenerate output)

            for _ in 0 ..< effectiveMaxTokens {
                try Task.checkCancellation()

                // Sample token from logits (builds computation graph, no sync yet)
                let token = sampleToken(logits: logits, temperature: temperature)

                // CRITICAL: Prepare next step BEFORE calling item()
                // item() forces GPU sync, so we want next forward pass queued first
                let nextToken = token.asType(.int32).expandedDimensions(axis: 0).expandedDimensions(axis: 0)
                let nextEmbeds = model.model.embedTokens(nextToken)

                // Queue next forward pass (uses .none mask mode for single-token generation)
                (logits, cache) = model(
                    inputIds: nextToken,
                    inputEmbeddings: nextEmbeds,
                    cache: cache
                )
                asyncEval(logits, cache)  // Materialize logits + updated cache for next step

                // NOW extract token ID - this syncs with current token computation
                // GPU is already working on next logits while we do CPU work
                let tokenId = token.item(Int.self)

                // Check for EOS (end of sequence)
                if tokenizer.isEosToken(tokenId) {
                    break
                }

                // Repetition detection: stop if model gets stuck in a loop
                if tokenId == lastToken {
                    repetitionCount += 1
                    if repetitionCount >= maxRepetition {
                        break
                    }
                } else {
                    repetitionCount = 0
                    lastToken = tokenId
                }

                generatedTokens.append(tokenId)
            }

            // Clear GPU memory (intermediate activations, not model weights)
            MLX.Memory.clearCache()

            // ─────────────────────────────────────────────────────────────────────
            // Phase 5: Decode and Clean Output
            // ─────────────────────────────────────────────────────────────────────
            let rawText = tokenizer.decode(generatedTokens)
            let parsed = tokenizer.parseOutput(rawText)
            let cleanedText = parsed.text
            func normalizeLanguage(_ value: String?) -> String? {
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return nil }
                if trimmed.lowercased() == "auto" { return nil }
                return trimmed
            }
            let resolvedLanguage = normalizeLanguage(parsed.language) ?? normalizeLanguage(language)

            let processingTime = CFAbsoluteTimeGetCurrent() - startTime

            return TranscriptionResult(
                text: cleanedText,
                language: resolvedLanguage,
                processingTime: processingTime,
                audioDuration: audioDuration
            )
        }
    }

    /// Transcribe audio file to text
    ///
    /// - Parameters:
    ///   - url: URL to audio file
    ///   - language: Target language
    ///   - maxTokens: Maximum tokens to generate
    ///   - temperature: Sampling temperature
    /// - Returns: Transcription result
    public func transcribe(
        file url: URL,
        language: String? = nil,
        context: String? = nil,
        maxTokens: Int = 4096,
        temperature: Float = 0.0
    ) throws -> TranscriptionResult {
        let audio = try loadAudio(from: url)
        return try transcribe(
            audio: audio,
            language: language,
            context: context,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }

    // MARK: - Sampling

    /// Sample next token from logits
    ///
    /// ## Sampling Strategies
    /// - **Greedy (temperature ≤ 0)**: Always pick highest probability token. Deterministic, fast.
    /// - **Temperature sampling (temperature > 0)**: Sample from scaled probability distribution.
    ///   Higher temperature = more random, lower = more focused.
    ///
    /// ## Gumbel-Max Trick
    /// Instead of expensive multinomial sampling, we use the Gumbel-max trick:
    /// `argmax(log(probs) + gumbel_noise)` is equivalent to sampling from the distribution.
    /// This is more efficient on GPU as it avoids cumsum/searchsorted operations.
    ///
    /// - Parameters:
    ///   - logits: Model output logits, shape (batch, seq_len, vocab_size)
    ///   - temperature: Sampling temperature (0 = greedy)
    /// - Returns: Sampled token ID as MLXArray (scalar)
    private func sampleToken(logits: MLXArray, temperature: Float) -> MLXArray {
        // Extract logits for last position: (batch, seq_len, vocab) -> (vocab,)
        let lastLogits = logits[0, -1, 0...]

        if temperature <= 0.0 {
            // Greedy: pick highest probability token
            return MLX.argMax(lastLogits, axis: -1)
        } else {
            // Temperature scaling: higher temp = flatter distribution
            let scaledLogits = lastLogits / temperature
            let probs = MLX.softmax(scaledLogits, axis: -1)

            // Gumbel-max trick for efficient GPU sampling
            // Gumbel(0,1) = -log(-log(U)) where U ~ Uniform(0,1)
            let shape = probs.shape
            let uniformRandom = MLXRandom.uniform(low: Float(0), high: Float(1), shape)
            // Add small epsilon to avoid log(0)
            let gumbel = -MLX.log(-MLX.log(uniformRandom + 1e-10) + 1e-10)
            return MLX.argMax(MLX.log(probs + 1e-10) + gumbel, axis: -1)
        }
    }

    private static func mapQuantizationMode(_ raw: String?) -> QuantizationMode {
        let mode = (raw ?? "affine").lowercased()
        switch mode {
        case "affine":
            return .affine
        case "mxfp4":
            return .mxfp4
        case "mxfp8":
            return .mxfp8
        case "nvfp4":
            return .nvfp4
        default:
            return .affine
        }
    }
}
