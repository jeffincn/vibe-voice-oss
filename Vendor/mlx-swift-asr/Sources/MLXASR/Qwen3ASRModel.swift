// Copyright © 2025 OnType
// Qwen3-ASR main model implementation

import Foundation
import MLX
import MLXLMCommon
import MLXNN

// MARK: - Qwen3 ASR Model

/// Qwen3-ASR Model combining audio encoder with Qwen3 text decoder
public final class Qwen3ASRModel: Module {
    public let config: Qwen3ASRConfig

    @ModuleInfo(key: "audio_tower") var audioTower: AudioEncoder
    @ModuleInfo var model: Qwen3TextModel
    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    public init(config: Qwen3ASRConfig) {
        self.config = config

        _audioTower.wrappedValue = AudioEncoder(config: config.audioConfig)
        _model.wrappedValue = Qwen3TextModel(config: config.textConfig)

        if !config.textConfig.tieWordEmbeddings {
            _lmHead.wrappedValue = Linear(
                config.textConfig.hiddenSize,
                config.textConfig.vocabSize,
                bias: false
            )
        } else {
            _lmHead.wrappedValue = nil
        }
    }

    /// Audio sample rate (16kHz)
    public var sampleRate: Int { 16000 }

    /// Number of transformer layers
    public var numLayers: Int { config.textConfig.numHiddenLayers }

    // MARK: - Audio Encoding

    /// Encode audio features through the audio tower
    public func getAudioFeatures(
        inputFeatures: MLXArray,
        featureAttentionMask: MLXArray? = nil
    ) -> MLXArray {
        audioTower(inputFeatures, featureAttentionMask: featureAttentionMask)
    }

    // MARK: - Embedding Building

    /// Build input embeddings by merging audio features at audio token positions
    public func buildInputsEmbeds(
        inputIds: MLXArray,
        audioFeatures: MLXArray
    ) -> MLXArray {
        let inputsEmbeds = model.embedTokens(inputIds)
        let audioFeaturesTyped = audioFeatures.asType(inputsEmbeds.dtype)

        // Find positions where audio tokens should be inserted
        let audioTokenMask = inputIds .== MLXArray(config.audioTokenId)

        // Check if there are any audio tokens to replace
        guard audioTokenMask.any().item() else {
            return inputsEmbeds
        }

        let (batchSize, seqLen, hiddenDim) = (
            inputsEmbeds.shape[0],
            inputsEmbeds.shape[1],
            inputsEmbeds.shape[2]
        )


        // Flatten for processing
        let flatMask = audioTokenMask.reshaped([seqLen])
        let flatEmbeds = inputsEmbeds.reshaped([seqLen, hiddenDim])

        // Count audio tokens
        let numAudioTokens = flatMask.sum().item(Int.self)
        let numAudioFeatures = audioFeaturesTyped.shape[0]


        guard numAudioTokens > 0 else {
            return inputsEmbeds
        }

        // Build audio embeddings array that matches the sequence length
        // For non-audio positions, we'll use the original embeddings
        // For audio positions, we need to use the audio features in order

        // Create cumsum of mask to get audio token index at each position
        let audioCumsum = MLX.cumsum(flatMask.asType(.int32), axis: 0) - 1

        // Create indices for gathering: audio positions get their corresponding audio feature index
        // Non-audio positions will be clamped to valid range but won't be used
        let audioIndices = MLX.clip(audioCumsum, min: 0, max: numAudioFeatures - 1)

        // Gather audio features at computed indices
        let gatheredAudio = audioFeaturesTyped[audioIndices]

        // Expand mask to match hidden dimension for broadcasting
        let expandedMask = flatMask.expandedDimensions(axis: -1).asType(gatheredAudio.dtype)

        // Use conditional selection: where mask is true, use audio features; otherwise use text embeddings
        let result = expandedMask * gatheredAudio + (1.0 - expandedMask) * flatEmbeds

        return result.reshaped([batchSize, seqLen, hiddenDim])
    }

    // MARK: - Forward Pass

    /// Forward pass with audio features
    public func callAsFunction(
        inputIds: MLXArray,
        inputEmbeddings: MLXArray? = nil,
        inputFeatures: MLXArray? = nil,
        featureAttentionMask: MLXArray? = nil,
        cache: [KVCacheSimple]? = nil
    ) -> (MLXArray, [KVCacheSimple]) {
        var inputsEmbeds: MLXArray
        if let embeddings = inputEmbeddings {
            inputsEmbeds = embeddings
        } else {
            inputsEmbeds = model.embedTokens(inputIds)
        }

        // Process audio features on first pass (no cache or empty cache)
        let isFirstPass = cache == nil || cache?.first?.offset == 0
        if let features = inputFeatures, isFirstPass {
            let audioFeatures = getAudioFeatures(
                inputFeatures: features,
                featureAttentionMask: featureAttentionMask
            )
            inputsEmbeds = buildInputsEmbeds(inputIds: inputIds, audioFeatures: audioFeatures)
        }

        // Forward through text model
        let (hiddenStates, newCache) = model(
            inputEmbeddings: inputsEmbeds,
            cache: cache
        )

        // Compute logits
        let logits: MLXArray
        if config.textConfig.tieWordEmbeddings {
            logits = model.embedTokens.asLinear(hiddenStates)
        } else if let lmHead {
            logits = lmHead(hiddenStates)
        } else {
            fatalError("LM head not initialized and embeddings not tied")
        }

        return (logits, newCache)
    }

    // MARK: - Generation Support

    /// Create KV cache for generation
    public func makeCache() -> [KVCacheSimple] {
        (0 ..< numLayers).map { _ in KVCacheSimple() }
    }

    /// Get embedding layer for input preprocessing
    public func getInputEmbeddings() -> Embedding {
        model.embedTokens
    }

    // MARK: - Weight Loading

    /// Sanitize weights from HuggingFace format to MLX format
    public static func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var sanitized: [String: MLXArray] = [:]
        let isFormatted = !weights.keys.contains { $0.hasPrefix("thinker.") }

        for (key, value) in weights {
            var k = key
            var v = value

            // Remove thinker. prefix if present
            if k.hasPrefix("thinker.") {
                k = String(k.dropFirst("thinker.".count))
            }

            // Skip lm_head.weight (handled by tied embeddings)
            if k == "lm_head.weight" {
                continue
            }

            // Transpose conv2d weights from PyTorch OIHW to MLX OHWI
            if !isFormatted && k.contains("conv2d") && k.contains("weight") && v.ndim == 4 {
                v = v.transposed(0, 2, 3, 1)
            }

            sanitized[k] = v
        }

        return sanitized
    }

    /// Load model from a directory containing config.json and weights
    public static func load(from directory: URL) throws -> Qwen3ASRModel {
        let config = try Qwen3ASRConfig.load(from: directory)
        let model = Qwen3ASRModel(config: config)

        // Load weights
        let weightsURL = directory.appendingPathComponent("weights.safetensors")
        if FileManager.default.fileExists(atPath: weightsURL.path) {
            let weights = try MLX.loadArrays(url: weightsURL)
            let sanitized = sanitize(weights: weights)

            // Apply weights
            try model.update(parameters: ModuleParameters.unflattened(sanitized), verify: .noUnusedKeys)
        }

        return model
    }
}

// MARK: - Compute Output Lengths Helper

/// Calculate output sequence length after audio encoder convolutions
func getAudioEncoderOutputLengths(_ inputLengths: MLXArray) -> MLXArray {
    // Output length calculation for 3 stride-2 convolutions
    let inputLengthsLeave = inputLengths % 100
    let featLengths = MLX.floor((inputLengthsLeave - 1).asType(.float32) / 2.0).asType(.int32) + 1
    let step1 = MLX.floor((featLengths - 1).asType(.float32) / 2.0).asType(.int32) + 1
    let step2 = MLX.floor((step1 - 1).asType(.float32) / 2.0).asType(.int32) + 1
    let outputLengths = step2 + (inputLengths / 100) * 13
    return outputLengths
}
