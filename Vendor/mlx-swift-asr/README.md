# mlx-swift-asr

On-device speech recognition for Apple Silicon, powered by [MLX](https://github.com/ml-explore/mlx-swift).

Built and maintained by [OnType](https://github.com/ontypehq) — the fastest voice input tool for macOS.

## Features

- **Qwen3-ASR** model support (0.6B, 1.7B)
- Optimized mel spectrogram computation on MLX
- Actor-based thread-safe API
- Metal shader warmup for consistent first-inference latency
- 16kHz audio input with built-in resampling

## Requirements

- macOS 15+ (Sequoia)
- Apple Silicon (M1 or later)
- Swift 6.2+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ontypehq/mlx-swift-asr", branch: "main"),
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MLXASR", package: "mlx-swift-asr"),
    ]
)
```

## Usage

```swift
import MLXASR

// Load model from a local directory
let stt = Qwen3ASRSTT()
try await stt.loadModel(from: modelDirectory)

// Warmup Metal shaders (call once, ~3-5s)
try await stt.warmup()

// Transcribe audio
let result = try await stt.transcribe(audioFile: audioURL)
print(result.text)
print("RTF: \(result.rtf)") // Real-time factor (<1.0 = faster than real-time)
```

## Model

Download a compatible Qwen3-ASR model (GGUF/safetensors quantized for MLX):

| Model | Size | Notes |
|-------|------|-------|
| Qwen3-ASR-0.6B-6bit | ~400MB | Recommended for most use cases |
| Qwen3-ASR-1.7B | ~1.7GB | Higher accuracy |

## Benchmark

Qwen3-ASR-0.6B-6bit on Apple M1 Pro, macOS 15.3. Numbers are **inference only** (excluding model load and Metal warmup).

| Audio Duration | Inference Time | RTF | Speed |
|---------------|---------------|-----|-------|
| 1.58s | 0.27s | 0.172 | **5.8x** real-time |
| 2.56s | 0.41s | 0.159 | **6.3x** real-time |
| 0.98s | 0.26s | 0.264 | **3.8x** real-time |
| 1.19s | 0.29s | 0.239 | **4.2x** real-time |

Typical RTF range: **0.15–0.27** (3.7–6.3x real-time), competitive with the Python MLX implementation while running as a native Swift library with no Python overhead.

### Run benchmarks yourself

```bash
swift test --filter Benchmark
```

## Architecture

```
Audio (WAV/PCM16) → Resample 16kHz → Mel Spectrogram (128 bins)
    → Audio Encoder (Transformer) → Audio Embeddings
    → Text Decoder (Qwen3 GQA + RoPE) → Tokens → Text
```

Key implementation details:
- Mel spectrogram matches WhisperFeatureExtractor (400-sample FFT, 160-sample hop)
- Grouped Query Attention (GQA) for memory-efficient decoding
- QK Normalization before RoPE (Qwen3-specific)
- SwiGLU activation in MLP layers

## License

MIT
