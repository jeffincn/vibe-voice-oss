// Copyright © 2025 OnType
// Qwen3-ASR Text Decoder implementation (Qwen3 LLM)
//
// ARCHITECTURE NOTES:
// This file implements the Qwen3 transformer architecture for the ASR text decoder.
// Key features:
//
// 1. Grouped Query Attention (GQA): Multiple query heads share fewer KV heads,
//    reducing memory bandwidth during generation while maintaining quality.
//    - 0.6B model: 16 Q heads, 2 KV heads (8:1 ratio)
//    - 1.7B model: 32 Q heads, 4 KV heads (8:1 ratio)
//
// 2. QK Normalization: Qwen3 applies RMSNorm to Q and K BEFORE RoPE.
//    This stabilizes attention scores and improves training. PITFALL: Missing
//    QK norm produces garbage output - always verify config has q_norm/k_norm.
//
// 3. RoPE (Rotary Position Embedding): Position information encoded via rotation,
//    enabling length extrapolation beyond training context.
//
// 4. SwiGLU MLP: gate * silu(gate) * up projection, more expressive than standard FFN.
//
// PERFORMANCE OPTIMIZATION:
// The mask parameter uses `MLXFast.ScaledDotProductAttentionMaskMode` instead of
// actual MLXArray masks. This avoids allocating large (seq_len, seq_len) arrays:
// - `.causal`: Symbolic causal mask, handled efficiently in Metal kernel
// - `.none`: No mask needed (single-token generation with KV cache)

import Foundation
import MLX
import MLXLMCommon
import MLXNN

// MARK: - Qwen3 Attention

/// Qwen3 attention with Grouped Query Attention (GQA) and RoPE
///
/// ## Key Differences from Standard Attention
/// 1. **GQA**: nKVHeads < nHeads, KV heads are broadcast to match Q heads
/// 2. **QK Norm**: RMSNorm applied to Q and K before RoPE (Qwen3-specific)
/// 3. **RoPE**: Applied after QK norm, before attention computation
final class Qwen3TextAttention: Module {
    let config: TextDecoderConfig
    let nHeads: Int
    let nKVHeads: Int
    let headDim: Int
    let scale: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear

    // QK normalization (per-head RMSNorm) - Qwen3 specific
    @ModuleInfo(key: "q_norm") var qNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var kNorm: RMSNorm

    // Rotary embeddings
    let rope: RoPE

    init(config: TextDecoderConfig) {
        self.config = config
        nHeads = config.numAttentionHeads
        nKVHeads = config.numKeyValueHeads
        headDim = config.headDim
        scale = pow(Float(headDim), -0.5)

        let dim = config.hiddenSize

        // Projections (bias depends on config)
        _qProj.wrappedValue = Linear(dim, nHeads * headDim, bias: config.attentionBias)
        _kProj.wrappedValue = Linear(dim, nKVHeads * headDim, bias: config.attentionBias)
        _vProj.wrappedValue = Linear(dim, nKVHeads * headDim, bias: config.attentionBias)
        _oProj.wrappedValue = Linear(nHeads * headDim, dim, bias: config.attentionBias)

        // QK normalization
        _qNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
        _kNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: config.rmsNormEps)

        // Rotary embeddings
        rope = RoPE(dimensions: headDim, traditional: false, base: config.ropeTheta)
    }

    /// Forward pass for attention layer
    ///
    /// - Parameters:
    ///   - x: Input tensor, shape (batch, seq_len, hidden_dim)
    ///   - mask: Attention mask mode (see PERFORMANCE note below)
    ///   - cache: KV cache for autoregressive generation
    /// - Returns: Output tensor, shape (batch, seq_len, hidden_dim)
    ///
    /// ## PERFORMANCE: Mask Mode Selection
    /// - `.causal`: Use for prefill (multiple tokens). MLX generates symbolic
    ///   causal mask internally - no memory allocation for (seq, seq) array.
    /// - `.none`: Use for single-token generation. With KV cache, the new token
    ///   can attend to all cached positions, no mask needed.
    ///
    /// PITFALL: Using `.causal` for single-token generation works but wastes
    /// computation. Using `.none` for prefill produces incorrect output!
    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode = .none,
        cache: KVCacheSimple? = nil
    ) -> MLXArray {
        let (B, L, _) = (x.shape[0], x.shape[1], x.shape[2])

        // Project to Q, K, V
        var queries = qProj(x)
        var keys = kProj(x)
        var values = vProj(x)

        // Reshape: (B, L, heads*dim) -> (B, heads, L, dim)
        queries = queries.reshaped([B, L, nHeads, headDim]).transposed(0, 2, 1, 3)
        keys = keys.reshaped([B, L, nKVHeads, headDim]).transposed(0, 2, 1, 3)
        values = values.reshaped([B, L, nKVHeads, headDim]).transposed(0, 2, 1, 3)

        // Qwen3-specific: Apply QK normalization BEFORE RoPE
        // This stabilizes attention scores in deep networks
        queries = qNorm(queries)
        keys = kNorm(keys)

        // Apply RoPE with position offset from cache
        // offset = total tokens seen so far (for correct position encoding)
        let offset = cache?.offset ?? 0
        queries = rope(queries, offset: offset)
        keys = rope(keys, offset: offset)

        // Update KV cache (extends keys/values with cached history)
        if let cache {
            (keys, values) = cache.update(keys: keys, values: values)
        }

        // Scaled dot-product attention
        // GQA broadcasting: nKVHeads < nHeads, MLXFast handles the broadcast
        let output = MLXFast.scaledDotProductAttention(
            queries: queries,
            keys: keys,
            values: values,
            scale: scale,
            mask: mask
        )

        // Reshape back: (B, heads, L, dim) -> (B, L, heads*dim)
        let outputReshaped = output.transposed(0, 2, 1, 3).reshaped([B, L, -1])

        return oProj(outputReshaped)
    }
}

// MARK: - Qwen3 MLP

/// Qwen3 MLP with SwiGLU activation
///
/// ## Architecture: SwiGLU
/// `output = down(silu(gate(x)) * up(x))`
///
/// SwiGLU uses gated activation which is more expressive than standard ReLU/GELU FFN.
/// The gate and up projections expand to intermediate_size (typically 4x hidden_size),
/// then down projects back.
///
/// ## Parameter Count
/// - Standard FFN: 2 * hidden * intermediate
/// - SwiGLU: 3 * hidden * intermediate (gate + up + down)
final class Qwen3TextMLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    init(config: TextDecoderConfig) {
        let dim = config.hiddenSize
        let hiddenDim = config.intermediateSize

        // All projections are bias-free (common in modern LLMs)
        _gateProj.wrappedValue = Linear(dim, hiddenDim, bias: false)
        _upProj.wrappedValue = Linear(dim, hiddenDim, bias: false)
        _downProj.wrappedValue = Linear(hiddenDim, dim, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        // SwiGLU: silu(gate) acts as a learned gating mechanism
        downProj(silu(gateProj(x)) * upProj(x))
    }
}

// MARK: - Qwen3 Transformer Block

/// Single Qwen3 transformer block with pre-norm
final class Qwen3TextDecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var selfAttn: Qwen3TextAttention
    @ModuleInfo var mlp: Qwen3TextMLP
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm

    init(config: TextDecoderConfig) {
        _selfAttn.wrappedValue = Qwen3TextAttention(config: config)
        _mlp.wrappedValue = Qwen3TextMLP(config: config)
        _inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        _postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode = .none,
        cache: KVCacheSimple? = nil
    ) -> MLXArray {
        // Self-attention with pre-norm and residual
        var r = x
        var h = inputLayerNorm(x)
        let attnOut = selfAttn(h, mask: mask, cache: cache)
        h = r + attnOut

        // MLP with pre-norm and residual
        r = h
        h = postAttentionLayerNorm(h)
        h = mlp(h)
        h = r + h

        return h
    }
}

// MARK: - Qwen3 Text Model

/// Qwen3 transformer model (without LM head)
///
/// This is the core transformer stack: embedding -> N transformer blocks -> final norm.
/// The LM head (for token prediction) is in `Qwen3TextDecoder`.
final class Qwen3TextModel: Module {
    let config: TextDecoderConfig

    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo var layers: [Qwen3TextDecoderLayer]
    @ModuleInfo var norm: RMSNorm

    init(config: TextDecoderConfig) {
        self.config = config

        _embedTokens.wrappedValue = Embedding(embeddingCount: config.vocabSize, dimensions: config.hiddenSize)
        _layers.wrappedValue = (0 ..< config.numHiddenLayers).map { _ in
            Qwen3TextDecoderLayer(config: config)
        }
        _norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    /// Forward pass with optional pre-computed embeddings for audio
    ///
    /// - Parameters:
    ///   - inputIds: Token IDs, shape (batch, seq_len). Mutually exclusive with inputEmbeddings.
    ///   - inputEmbeddings: Pre-computed embeddings (for audio-text fusion). Shape (batch, seq_len, hidden).
    ///   - cache: KV cache from previous generation steps. Pass nil for first call.
    /// - Returns: Tuple of (hidden states, updated cache)
    func callAsFunction(
        inputIds: MLXArray? = nil,
        inputEmbeddings: MLXArray? = nil,
        cache: [KVCacheSimple]? = nil
    ) -> (MLXArray, [KVCacheSimple]) {
        var h: MLXArray
        if let embeddings = inputEmbeddings {
            h = embeddings
        } else if let ids = inputIds {
            h = embedTokens(ids)
        } else {
            fatalError("Either inputIds or inputEmbeddings must be provided")
        }

        // ─────────────────────────────────────────────────────────────────────
        // PERFORMANCE CRITICAL: Automatic mask mode selection
        //
        // Prefill (seq_len > 1): Use .causal
        // - Multiple tokens need causal masking to prevent future token attention
        // - .causal is a symbolic hint, MLX generates mask efficiently in kernel
        //
        // Generation (seq_len == 1): Use .none
        // - Single new token with KV cache can attend to ALL previous tokens
        // - No mask needed - the cache already contains only valid positions
        //
        // PITFALL: Using .causal for seq_len=1 works but wastes computation
        // PITFALL: Using .none for seq_len>1 produces incorrect output!
        // ─────────────────────────────────────────────────────────────────────
        let maskMode: MLXFast.ScaledDotProductAttentionMaskMode = h.shape[1] > 1 ? .causal : .none

        // Initialize cache if not provided (first call)
        let cacheList = cache ?? (0 ..< layers.count).map { _ in KVCacheSimple() }

        // Process through transformer layers
        for (i, layer) in layers.enumerated() {
            h = layer(h, mask: maskMode, cache: cacheList[i])
        }

        // Final layer norm
        return (norm(h), cacheList)
    }
}

// MARK: - Qwen3 Text Decoder (with LM head)

/// Qwen3 model with language modeling head for ASR
final class Qwen3TextDecoder: Module {
    let config: TextDecoderConfig
    @ModuleInfo var model: Qwen3TextModel

    // LM head (only if not using tied embeddings)
    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    init(config: TextDecoderConfig) {
        self.config = config
        _model.wrappedValue = Qwen3TextModel(config: config)

        if !config.tieWordEmbeddings {
            _lmHead.wrappedValue = Linear(config.hiddenSize, config.vocabSize, bias: false)
        } else {
            _lmHead.wrappedValue = nil
        }
    }

    /// Forward pass returning logits
    func callAsFunction(
        inputIds: MLXArray? = nil,
        inputEmbeddings: MLXArray? = nil,
        cache: [KVCacheSimple]? = nil
    ) -> (MLXArray, [KVCacheSimple]) {
        let (out, newCache) = model(
            inputIds: inputIds,
            inputEmbeddings: inputEmbeddings,
            cache: cache
        )

        let logits: MLXArray
        if config.tieWordEmbeddings {
            logits = model.embedTokens.asLinear(out)
        } else if let lmHead {
            logits = lmHead(out)
        } else {
            fatalError("LM head not initialized and embeddings not tied")
        }

        return (logits, newCache)
    }

    /// Get the input embedding layer
    func getInputEmbeddings() -> Embedding {
        model.embedTokens
    }
}
