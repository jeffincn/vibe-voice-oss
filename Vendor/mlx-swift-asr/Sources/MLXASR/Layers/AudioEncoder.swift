// Copyright © 2025 OnType
// Qwen3-ASR Audio Encoder implementation

import Foundation
import MLX
import MLXNN

// MARK: - Sinusoidal Position Embedding

/// Sinusoidal position embeddings for the audio encoder
final class SinusoidalPositionEmbedding: Module {
    let channels: Int
    let maxTimescale: Float
    let invTimescales: MLXArray

    init(length _: Int, channels: Int, maxTimescale: Float = 10000.0) {
        precondition(channels % 2 == 0, "SinusoidalPositionEmbedding needs even channels input")

        self.channels = channels
        self.maxTimescale = maxTimescale

        let logTimescaleIncrement = log(maxTimescale) / Float(channels / 2 - 1)
        invTimescales = MLX.exp(
            -logTimescaleIncrement * MLXArray(0 ..< (channels / 2)).asType(.float32)
        )
    }

    func callAsFunction(_ seqlen: Int) -> MLXArray {
        // Dynamically compute positional embeddings for any length
        let positions = MLXArray(0 ..< seqlen).asType(.float32).expandedDimensions(axis: 1)
        let scaledTime = positions * invTimescales.expandedDimensions(axis: 0)

        return MLX.concatenated(
            [MLX.sin(scaledTime), MLX.cos(scaledTime)],
            axis: 1
        )
    }
}

// MARK: - Audio Attention

/// Multi-headed attention for audio encoder
final class AudioAttention: Module {
    let embedDim: Int
    let numHeads: Int
    let headDim: Int
    let scaling: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear

    init(config: AudioEncoderConfig) {
        embedDim = config.dModel
        numHeads = config.encoderAttentionHeads
        headDim = embedDim / numHeads
        scaling = pow(Float(headDim), -0.5)

        precondition(
            headDim * numHeads == embedDim,
            "embed_dim must be divisible by num_heads"
        )

        _qProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
        _kProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
        _vProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
        _outProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
    }

    func callAsFunction(_ hiddenStates: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        let (bsz, seqLen, _) = (hiddenStates.shape[0], hiddenStates.shape[1], hiddenStates.shape[2])

        var queryStates = qProj(hiddenStates) * scaling
        var keyStates = kProj(hiddenStates)
        var valueStates = vProj(hiddenStates)

        queryStates = queryStates
            .reshaped(bsz, seqLen, numHeads, headDim)
            .transposed(0, 2, 1, 3)
        keyStates = keyStates
            .reshaped(bsz, seqLen, numHeads, headDim)
            .transposed(0, 2, 1, 3)
        valueStates = valueStates
            .reshaped(bsz, seqLen, numHeads, headDim)
            .transposed(0, 2, 1, 3)

        let attnOutput = MLXFast.scaledDotProductAttention(
            queries: queryStates,
            keys: keyStates,
            values: valueStates,
            scale: 1.0,
            mask: mask
        )

        let output = attnOutput
            .transposed(0, 2, 1, 3)
            .reshaped(bsz, seqLen, embedDim)

        return outProj(output)
    }
}

// MARK: - Audio Encoder Layer

/// A single transformer encoder layer for audio
final class AudioEncoderLayer: Module {
    let embedDim: Int

    @ModuleInfo(key: "self_attn") var selfAttn: AudioAttention
    @ModuleInfo(key: "self_attn_layer_norm") var selfAttnLayerNorm: LayerNorm
    @ModuleInfo var fc1: Linear
    @ModuleInfo var fc2: Linear
    @ModuleInfo(key: "final_layer_norm") var finalLayerNorm: LayerNorm

    init(config: AudioEncoderConfig) {
        embedDim = config.dModel

        _selfAttn.wrappedValue = AudioAttention(config: config)
        _selfAttnLayerNorm.wrappedValue = LayerNorm(dimensions: embedDim)
        _fc1.wrappedValue = Linear(embedDim, config.encoderFfnDim)
        _fc2.wrappedValue = Linear(config.encoderFfnDim, embedDim)
        _finalLayerNorm.wrappedValue = LayerNorm(dimensions: embedDim)
    }

    func callAsFunction(_ hiddenStates: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        var x = hiddenStates

        // Self attention with pre-norm
        let residual1 = x
        x = selfAttnLayerNorm(x)
        x = selfAttn(x, mask: mask)
        x = residual1 + x

        // FFN with pre-norm
        let residual2 = x
        x = finalLayerNorm(x)
        x = gelu(fc1(x))
        x = fc2(x)
        x = residual2 + x

        return x
    }
}

// MARK: - Audio Encoder

/// Qwen3-ASR Audio Encoder with Conv2d frontend and transformer layers
final class AudioEncoder: Module {
    let config: AudioEncoderConfig
    let numMelBins: Int
    let maxSourcePositions: Int
    let embedScale: Float
    let nWindow: Int
    let nWindowInfer: Int

    @ModuleInfo var conv2d1: Conv2d
    @ModuleInfo var conv2d2: Conv2d
    @ModuleInfo var conv2d3: Conv2d
    @ModuleInfo(key: "conv_out") var convOut: Linear
    @ModuleInfo(key: "positional_embedding") var positionalEmbedding: SinusoidalPositionEmbedding
    @ModuleInfo var layers: [AudioEncoderLayer]
    @ModuleInfo(key: "ln_post") var lnPost: LayerNorm
    @ModuleInfo var proj1: Linear
    @ModuleInfo var proj2: Linear

    init(config: AudioEncoderConfig) {
        self.config = config
        let embedDim = config.dModel
        numMelBins = config.numMelBins
        maxSourcePositions = config.maxSourcePositions
        embedScale = config.scaleEmbedding ? sqrt(Float(embedDim)) : 1.0
        nWindow = config.nWindow
        nWindowInfer = config.nWindowInfer

        _conv2d1.wrappedValue = Conv2d(
            inputChannels: 1,
            outputChannels: config.downsampleHiddenSize,
            kernelSize: IntOrPair(3),
            stride: IntOrPair(2),
            padding: IntOrPair(1)
        )
        _conv2d2.wrappedValue = Conv2d(
            inputChannels: config.downsampleHiddenSize,
            outputChannels: config.downsampleHiddenSize,
            kernelSize: IntOrPair(3),
            stride: IntOrPair(2),
            padding: IntOrPair(1)
        )
        _conv2d3.wrappedValue = Conv2d(
            inputChannels: config.downsampleHiddenSize,
            outputChannels: config.downsampleHiddenSize,
            kernelSize: IntOrPair(3),
            stride: IntOrPair(2),
            padding: IntOrPair(1)
        )

        // Calculate frequency dimension after 3 stride-2 convolutions
        let freqAfterConv = ((((config.numMelBins + 1) / 2) + 1) / 2 + 1) / 2
        _convOut.wrappedValue = Linear(config.downsampleHiddenSize * freqAfterConv, embedDim, bias: false)

        _positionalEmbedding.wrappedValue = SinusoidalPositionEmbedding(
            length: maxSourcePositions,
            channels: embedDim
        )

        _layers.wrappedValue = (0 ..< config.encoderLayers).map { _ in
            AudioEncoderLayer(config: config)
        }

        _lnPost.wrappedValue = LayerNorm(dimensions: embedDim)
        _proj1.wrappedValue = Linear(embedDim, embedDim)
        _proj2.wrappedValue = Linear(embedDim, config.outputDim)
    }

    /// Compute output length after convolutional layers
    private func getOutputLengths(_ inputLengths: MLXArray) -> MLXArray {
        let inputLengthsLeave = inputLengths % 100
        let featLengths = floorDiv(inputLengthsLeave - 1, 2) + 1
        let outputLengths = floorDiv(floorDiv(featLengths - 1, 2) + 1 - 1, 2) + 1 + (inputLengths / 100) * 13
        return outputLengths
    }

    /// Floor division matching Python semantics
    private func floorDiv(_ a: MLXArray, _ b: Int) -> MLXArray {
        MLX.floor(a.asType(.float32) / Float(b)).asType(.int32)
    }

    /// CPU-side output length for a single chunk after 3 stride-2 convolutions (no GPU sync)
    private static func convOutputLength(_ inputLen: Int) -> Int {
        let leave = inputLen % 100
        let feat = leave > 0 ? (leave - 1) / 2 + 1 : 0
        let s1 = feat > 0 ? (feat - 1) / 2 + 1 : 0
        let s2 = s1 > 0 ? (s1 - 1) / 2 + 1 : 0
        return s2 + (inputLen / 100) * 13
    }

    private func createBlockAttentionMask(seqLen: Int, cuSeqlens: [Int], dtype: DType) -> MLXArray {
        var mask = [Float](repeating: -1e9, count: seqLen * seqLen)
        for i in 0 ..< max(0, cuSeqlens.count - 1) {
            let start = cuSeqlens[i]
            let end = cuSeqlens[i + 1]
            guard start >= 0, end <= seqLen, end > start else { continue }
            for row in start ..< end {
                let rowOffset = row * seqLen
                for col in start ..< end {
                    mask[rowOffset + col] = 0.0
                }
            }
        }
        return MLXArray(mask)
            .reshaped([seqLen, seqLen])
            .asType(dtype)
            .expandedDimensions(axis: 0)
            .expandedDimensions(axis: 0)
    }

    func callAsFunction(_ inputFeatures: MLXArray, featureAttentionMask: MLXArray? = nil) -> MLXArray {
        let batchSize = inputFeatures.shape[0]
        let totalFrames = inputFeatures.shape[2]
        let chunkSize = max(1, nWindow * 2)

        var hiddenPerSample: [MLXArray] = []
        hiddenPerSample.reserveCapacity(batchSize)

        var afterCnnLens: [Int] = []
        afterCnnLens.reserveCapacity(batchSize)

        var maxLenAfterCnn = 1

        for sampleIdx in 0 ..< batchSize {
            let sampleFeatures = inputFeatures[sampleIdx]
            let featureLength: Int
            if let featureAttentionMask {
                let maskLength = featureAttentionMask[sampleIdx, 0...].sum().item(Int.self)
                featureLength = max(1, min(maskLength, totalFrames))
            } else {
                featureLength = totalFrames
            }

            let numChunks = max(1, (featureLength + chunkSize - 1) / chunkSize)

            var chunkLengths: [Int] = []
            chunkLengths.reserveCapacity(numChunks)
            var chunks: [MLXArray] = []
            chunks.reserveCapacity(numChunks)

            var pos = 0
            while pos < featureLength {
                let chunkEnd = min(pos + chunkSize, featureLength)
                let chunkLength = chunkEnd - pos
                chunkLengths.append(chunkLength)
                chunks.append(sampleFeatures[0..., pos ..< chunkEnd])
                pos = chunkEnd
            }

            let maxChunkLen = chunkLengths.max() ?? chunkSize
            var paddedChunks: [MLXArray] = []
            paddedChunks.reserveCapacity(chunks.count)
            for (chunkIndex, chunk) in chunks.enumerated() {
                let chunkLength = chunkLengths[chunkIndex]
                if chunkLength < maxChunkLen {
                    let padWidth = maxChunkLen - chunkLength
                    paddedChunks.append(
                        MLX.padded(
                            chunk,
                            widths: [IntOrPair((0, 0)), IntOrPair((0, padWidth))]
                        )
                    )
                } else {
                    paddedChunks.append(chunk)
                }
            }

            var x = MLX.stacked(paddedChunks, axis: 0).expandedDimensions(axis: -1)
            x = gelu(conv2d1(x))
            x = gelu(conv2d2(x))
            x = gelu(conv2d3(x))

            let freqAfterConv = x.shape[1]
            let timeAfterConv = x.shape[2]
            let channels = x.shape[3]
            maxLenAfterCnn = max(maxLenAfterCnn, timeAfterConv)

            x = x.transposed(0, 2, 3, 1).reshaped([x.shape[0], timeAfterConv, channels * freqAfterConv])
            x = convOut(x)
            x = x + positionalEmbedding(timeAfterConv).expandedDimensions(axis: 0)

            var chunkHiddenStates: [MLXArray] = []
            chunkHiddenStates.reserveCapacity(chunks.count)
            for (i, chunkLen) in chunkLengths.enumerated() {
                let validLen = max(1, Self.convOutputLength(chunkLen))
                chunkHiddenStates.append(x[i, 0 ..< validLen, 0...])
            }

            let sampleHidden = chunkHiddenStates.count == 1
                ? chunkHiddenStates[0]
                : MLX.concatenated(chunkHiddenStates, axis: 0)
            hiddenPerSample.append(sampleHidden)
            afterCnnLens.append(sampleHidden.shape[0])
        }

        let hiddenStatesFlat = hiddenPerSample.count == 1
            ? hiddenPerSample[0]
            : MLX.concatenated(hiddenPerSample, axis: 0)

        let inferScale = max(1, nWindowInfer / max(1, nWindow * 2))
        let windowAfterCnn = max(1, maxLenAfterCnn * inferScale)

        var cuChunkLens: [Int] = [0]
        for cnnLen in afterCnnLens {
            let numFullWindows = cnnLen / windowAfterCnn
            if numFullWindows > 0 {
                cuChunkLens.append(contentsOf: Array(repeating: windowAfterCnn, count: numFullWindows))
            }
            let remainder = cnnLen % windowAfterCnn
            if remainder != 0 {
                cuChunkLens.append(remainder)
            }
        }

        var cuSeqlens: [Int] = []
        cuSeqlens.reserveCapacity(cuChunkLens.count)
        var running = 0
        for chunkLen in cuChunkLens {
            running += chunkLen
            cuSeqlens.append(running)
        }

        let seqLen = hiddenStatesFlat.shape[0]
        let attentionMask = createBlockAttentionMask(
            seqLen: seqLen,
            cuSeqlens: cuSeqlens,
            dtype: hiddenStatesFlat.dtype
        )

        var hiddenStates = hiddenStatesFlat.expandedDimensions(axis: 0)
        for layer in layers {
            hiddenStates = layer(hiddenStates, mask: attentionMask)
        }

        hiddenStates = hiddenStates.squeezed(axis: 0)
        hiddenStates = lnPost(hiddenStates)
        hiddenStates = gelu(proj1(hiddenStates))
        hiddenStates = proj2(hiddenStates)
        return hiddenStates
    }
}
