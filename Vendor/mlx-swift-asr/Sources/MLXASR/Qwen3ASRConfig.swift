// Copyright © 2025 OnType
// Qwen3-ASR configuration types

import Foundation

// MARK: - Audio Encoder Config

public struct AudioEncoderConfig: Codable, Sendable {
    let numMelBins: Int
    let encoderLayers: Int
    let encoderAttentionHeads: Int
    let encoderFfnDim: Int
    let dModel: Int
    let dropout: Float
    let attentionDropout: Float
    let activationFunction: String
    let activationDropout: Float
    let scaleEmbedding: Bool
    let initializerRange: Float
    let maxSourcePositions: Int
    let nWindow: Int
    let outputDim: Int
    let nWindowInfer: Int
    let convChunksize: Int
    let downsampleHiddenSize: Int

    enum CodingKeys: String, CodingKey {
        case numMelBins = "num_mel_bins"
        case encoderLayers = "encoder_layers"
        case encoderAttentionHeads = "encoder_attention_heads"
        case encoderFfnDim = "encoder_ffn_dim"
        case dModel = "d_model"
        case dropout
        case attentionDropout = "attention_dropout"
        case activationFunction = "activation_function"
        case activationDropout = "activation_dropout"
        case scaleEmbedding = "scale_embedding"
        case initializerRange = "initializer_range"
        case maxSourcePositions = "max_source_positions"
        case nWindow = "n_window"
        case outputDim = "output_dim"
        case nWindowInfer = "n_window_infer"
        case convChunksize = "conv_chunksize"
        case downsampleHiddenSize = "downsample_hidden_size"
    }

    init(
        numMelBins: Int = 128,
        encoderLayers: Int = 24,
        encoderAttentionHeads: Int = 16,
        encoderFfnDim: Int = 4096,
        dModel: Int = 1024,
        dropout: Float = 0.0,
        attentionDropout: Float = 0.0,
        activationFunction: String = "gelu",
        activationDropout: Float = 0.0,
        scaleEmbedding: Bool = false,
        initializerRange: Float = 0.02,
        maxSourcePositions: Int = 1500,
        nWindow: Int = 50,
        outputDim: Int = 2048,
        nWindowInfer: Int = 800,
        convChunksize: Int = 500,
        downsampleHiddenSize: Int = 480
    ) {
        self.numMelBins = numMelBins
        self.encoderLayers = encoderLayers
        self.encoderAttentionHeads = encoderAttentionHeads
        self.encoderFfnDim = encoderFfnDim
        self.dModel = dModel
        self.dropout = dropout
        self.attentionDropout = attentionDropout
        self.activationFunction = activationFunction
        self.activationDropout = activationDropout
        self.scaleEmbedding = scaleEmbedding
        self.initializerRange = initializerRange
        self.maxSourcePositions = maxSourcePositions
        self.nWindow = nWindow
        self.outputDim = outputDim
        self.nWindowInfer = nWindowInfer
        self.convChunksize = convChunksize
        self.downsampleHiddenSize = downsampleHiddenSize
    }
}

// MARK: - Text Config (Qwen3 Decoder)

public struct TextDecoderConfig: Codable, Sendable {
    let modelType: String
    let vocabSize: Int
    let hiddenSize: Int
    let intermediateSize: Int
    let numHiddenLayers: Int
    let numAttentionHeads: Int
    let numKeyValueHeads: Int
    let headDim: Int
    let hiddenAct: String
    let maxPositionEmbeddings: Int
    let initializerRange: Float
    let rmsNormEps: Float
    let useCache: Bool
    let tieWordEmbeddings: Bool
    let ropeTheta: Float
    let attentionBias: Bool
    let attentionDropout: Float

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case vocabSize = "vocab_size"
        case hiddenSize = "hidden_size"
        case intermediateSize = "intermediate_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case hiddenAct = "hidden_act"
        case maxPositionEmbeddings = "max_position_embeddings"
        case initializerRange = "initializer_range"
        case rmsNormEps = "rms_norm_eps"
        case useCache = "use_cache"
        case tieWordEmbeddings = "tie_word_embeddings"
        case ropeTheta = "rope_theta"
        case attentionBias = "attention_bias"
        case attentionDropout = "attention_dropout"
    }

    init(
        modelType: String = "qwen3",
        vocabSize: Int = 151936,
        hiddenSize: Int = 2048,
        intermediateSize: Int = 6144,
        numHiddenLayers: Int = 28,
        numAttentionHeads: Int = 16,
        numKeyValueHeads: Int = 8,
        headDim: Int = 128,
        hiddenAct: String = "silu",
        maxPositionEmbeddings: Int = 65536,
        initializerRange: Float = 0.02,
        rmsNormEps: Float = 1e-6,
        useCache: Bool = true,
        tieWordEmbeddings: Bool = true,
        ropeTheta: Float = 1000000.0,
        attentionBias: Bool = false,
        attentionDropout: Float = 0.0
    ) {
        self.modelType = modelType
        self.vocabSize = vocabSize
        self.hiddenSize = hiddenSize
        self.intermediateSize = intermediateSize
        self.numHiddenLayers = numHiddenLayers
        self.numAttentionHeads = numAttentionHeads
        self.numKeyValueHeads = numKeyValueHeads
        self.headDim = headDim
        self.hiddenAct = hiddenAct
        self.maxPositionEmbeddings = maxPositionEmbeddings
        self.initializerRange = initializerRange
        self.rmsNormEps = rmsNormEps
        self.useCache = useCache
        self.tieWordEmbeddings = tieWordEmbeddings
        self.ropeTheta = ropeTheta
        self.attentionBias = attentionBias
        self.attentionDropout = attentionDropout
    }
}

// MARK: - Thinker Config (nested in HF config)

public struct ThinkerConfig: Codable, Sendable {
    let audioConfig: AudioEncoderConfig
    let textConfig: TextDecoderConfig
    let audioTokenId: Int
    let audioStartTokenId: Int
    let audioEndTokenId: Int

    enum CodingKeys: String, CodingKey {
        case audioConfig = "audio_config"
        case textConfig = "text_config"
        case audioTokenId = "audio_token_id"
        case audioStartTokenId = "audio_start_token_id"
        case audioEndTokenId = "audio_end_token_id"
    }
}

// MARK: - Model Config

public struct Qwen3ASRConfig: Codable, Sendable {
    let audioConfig: AudioEncoderConfig
    let textConfig: TextDecoderConfig
    let modelType: String
    let audioTokenId: Int
    let audioStartTokenId: Int
    let audioEndTokenId: Int
    let supportLanguages: [String]
    let quantizationConfig: Qwen3ASRQuantizationConfig?

    enum CodingKeys: String, CodingKey {
        case thinkerConfig = "thinker_config"
        case modelType = "model_type"
        case supportLanguages = "support_languages"
        case quantizationConfig = "quantization_config"
        case quantization = "quantization"
    }

    init(
        audioConfig: AudioEncoderConfig = AudioEncoderConfig(),
        textConfig: TextDecoderConfig = TextDecoderConfig(),
        modelType: String = "qwen3_asr",
        audioTokenId: Int = 151676,
        audioStartTokenId: Int = 151669,
        audioEndTokenId: Int = 151670,
        supportLanguages: [String] = [],
        quantizationConfig: Qwen3ASRQuantizationConfig? = nil
    ) {
        self.audioConfig = audioConfig
        self.textConfig = textConfig
        self.modelType = modelType
        self.audioTokenId = audioTokenId
        self.audioStartTokenId = audioStartTokenId
        self.audioEndTokenId = audioEndTokenId
        self.supportLanguages = supportLanguages
        self.quantizationConfig = quantizationConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "qwen3_asr"
        supportLanguages = try container.decodeIfPresent([String].self, forKey: .supportLanguages) ?? []

        // Parse nested thinker_config
        let thinker = try container.decode(ThinkerConfig.self, forKey: .thinkerConfig)
        audioConfig = thinker.audioConfig
        textConfig = thinker.textConfig
        audioTokenId = thinker.audioTokenId
        audioStartTokenId = thinker.audioStartTokenId
        audioEndTokenId = thinker.audioEndTokenId

        // Quantization metadata is optional and varies by exporter.
        // Some models include it under `quantization_config`, others under `quantization`.
        let q1 = try container.decodeIfPresent(Qwen3ASRQuantizationConfig.self, forKey: .quantizationConfig)
        let q2 = try container.decodeIfPresent(Qwen3ASRQuantizationConfig.self, forKey: .quantization)
        quantizationConfig = q1 ?? q2
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try container.encode(supportLanguages, forKey: .supportLanguages)

        let thinker = ThinkerConfig(
            audioConfig: audioConfig,
            textConfig: textConfig,
            audioTokenId: audioTokenId,
            audioStartTokenId: audioStartTokenId,
            audioEndTokenId: audioEndTokenId
        )
        try container.encode(thinker, forKey: .thinkerConfig)

        // Preserve quantization metadata if present.
        if let quantizationConfig {
            try container.encode(quantizationConfig, forKey: .quantizationConfig)
        }
    }

    /// Load config from a directory containing config.json
    static func load(from directory: URL) throws -> Qwen3ASRConfig {
        let configURL = directory.appendingPathComponent("config.json")
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        return try decoder.decode(Qwen3ASRConfig.self, from: data)
    }
}

// MARK: - Quantization Metadata

public struct Qwen3ASRQuantizationConfig: Codable, Sendable {
    let groupSize: Int
    let bits: Int
    let mode: String

    enum CodingKeys: String, CodingKey {
        case groupSize = "group_size"
        case bits
        case mode
    }
}
