// Copyright © 2025 OnType
// Qwen3-ASR Audio processing utilities
//
// ARCHITECTURE NOTES:
// This file handles audio loading, resampling, and mel spectrogram computation.
// Key design decisions:
//
// 1. Pre-computed constants: Hann window and mel filterbank are computed once
//    and cached as static properties. This avoids ~10ms overhead per transcription.
//
// 2. Thread safety: Static MLXArray properties use `nonisolated(unsafe)` because:
//    - They are computed once during lazy initialization
//    - They are never mutated after initialization
//    - Read operations on MLXArray are thread-safe
//    PITFALL: Do NOT add mutable operations to these static arrays!
//
// 3. Mel spectrogram matches WhisperFeatureExtractor:
//    - 128 mel bins (not 80 like original Whisper)
//    - 400-sample FFT window (25ms at 16kHz)
//    - 160-sample hop (10ms, 100fps)
//    - Slaney-style mel filterbank normalization
//
// 4. PITFALL - STFT frame count:
//    We drop the last STFT frame to match PyTorch's torch.stft behavior.
//    This is critical for compatibility with the trained model!

import AVFoundation
import Foundation
import MLX

// MARK: - Audio Constants

/// Qwen3-ASR audio hyperparameters
///
/// These match the WhisperFeatureExtractor configuration used during training.
/// Changing any of these will produce incompatible features!
public enum Qwen3ASRAudio {
    /// Sample rate in Hz (must resample all input to this rate)
    public static let sampleRate = 16000

    /// FFT window size in samples (25ms at 16kHz)
    public static let nFft = 400

    /// Hop length in samples (10ms at 16kHz = 100 frames/second)
    public static let hopLength = 160

    /// Number of mel frequency bins
    public static let nMels = 128

    /// Maximum audio chunk length in seconds
    public static let chunkLength = 30

    /// Maximum samples per chunk: 30s * 16000Hz = 480,000
    public static let nSamples = chunkLength * sampleRate

    /// Maximum frames per chunk: 480000 / 160 = 3000
    public static let nFrames = nSamples / hopLength

    // ─────────────────────────────────────────────────────────────────────────
    // Pre-computed Constants (PERFORMANCE OPTIMIZATION)
    //
    // These are computed once on first access and cached forever.
    // Using nonisolated(unsafe) because:
    // 1. Lazy static initialization is thread-safe in Swift
    // 2. After initialization, these are read-only
    // 3. MLXArray read operations are thread-safe
    //
    // PITFALL: Never mutate these arrays! If you need different parameters,
    // create new local arrays instead.
    // ─────────────────────────────────────────────────────────────────────────

    /// Pre-computed Hann window for STFT
    /// Shape: (nFft,) = (400,)
    public nonisolated(unsafe) static let hannWindow: MLXArray = {
        let length = nFft
        if length == 1 {
            return MLXArray([1.0])
        }
        // Hann window: 0.5 * (1 - cos(2π * n / (N-1)))
        let indices = (0 ..< length).map { Float($0) }
        let n = MLXArray(indices)
        let factor = 2.0 * Float.pi / Float(length - 1)
        let window = 0.5 * (1.0 - MLX.cos(n * factor))
        eval(window)  // Force computation and GPU transfer
        return window
    }()

    /// Pre-computed mel filterbank matrix
    /// Shape: (nMels, nFft/2+1) = (128, 201)
    /// Transposed during use: matmul(magnitudes, filters.T)
    public nonisolated(unsafe) static let melFilterbank: MLXArray = {
        let filters = computeMelFilters(
            sampleRate: sampleRate,
            nFft: nFft,
            nMels: nMels,
            fMin: 0.0,
            fMax: Float(sampleRate) / 2.0
        )
        eval(filters)  // Force computation and GPU transfer
        return filters
    }()
}

// MARK: - Audio Loading

/// Load audio file and resample to 16kHz mono
///
/// - Parameter url: URL to audio file
/// - Returns: Audio samples as Float array at 16kHz
public func loadAudio(from url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frameCount = AVAudioFrameCount(file.length)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw Qwen3ASRError.audioLoadFailed("Failed to create audio buffer")
    }

    try file.read(into: buffer)

    // Convert to mono if needed
    var samples: [Float]
    if let channelData = buffer.floatChannelData {
        let channelCount = Int(format.channelCount)
        let length = Int(buffer.frameLength)

        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: length))
        } else {
            // Average channels for mono
            samples = [Float](repeating: 0, count: length)
            for ch in 0 ..< channelCount {
                let channel = UnsafeBufferPointer(start: channelData[ch], count: length)
                for i in 0 ..< length {
                    samples[i] += channel[i]
                }
            }
            let scale = 1.0 / Float(channelCount)
            for i in 0 ..< length {
                samples[i] *= scale
            }
        }
    } else {
        throw Qwen3ASRError.audioLoadFailed("No float channel data")
    }

    // Resample if needed
    let sourceSampleRate = format.sampleRate
    if abs(sourceSampleRate - Double(Qwen3ASRAudio.sampleRate)) > 1.0 {
        samples = try resample(samples, from: sourceSampleRate, to: Double(Qwen3ASRAudio.sampleRate))
    }

    return samples
}

/// Resample audio using AVFoundation
private func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) throws -> [Float] {
    let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sourceSampleRate,
        channels: 1,
        interleaved: false
    )!

    let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
        throw Qwen3ASRError.audioLoadFailed("Failed to create audio converter")
    }

    let inputFrameCount = AVAudioFrameCount(samples.count)
    let ratio = targetSampleRate / sourceSampleRate
    let outputFrameCount = AVAudioFrameCount(Double(inputFrameCount) * ratio)

    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputFrameCount),
          let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount)
    else {
        throw Qwen3ASRError.audioLoadFailed("Failed to create resampling buffers")
    }

    inputBuffer.frameLength = inputFrameCount
    samples.withUnsafeBufferPointer { ptr in
        inputBuffer.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
    }

    var error: NSError?
    // AVAudioConverter may call the input block multiple times; provide the buffer once
    // then signal end-of-stream to avoid duplicating the input audio.
    var didProvideInput = false
    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
        if didProvideInput {
            outStatus.pointee = .endOfStream
            return nil
        }
        didProvideInput = true
        outStatus.pointee = .haveData
        return inputBuffer
    }

    if let error {
        throw Qwen3ASRError.audioLoadFailed("Resampling failed: \(error)")
    }

    return Array(UnsafeBufferPointer(start: outputBuffer.floatChannelData![0], count: Int(outputBuffer.frameLength)))
}

// MARK: - Mel Spectrogram

/// Pad or trim audio to target length
///
/// Used for batch processing to ensure consistent tensor shapes.
/// For streaming/variable-length input, this is typically not needed.
///
/// - Parameters:
///   - audio: Audio samples as 1D array
///   - length: Target length in samples (default: 30s at 16kHz = 480,000)
/// - Returns: Audio with exactly `length` samples (zero-padded or truncated)
public func padOrTrim(_ audio: MLXArray, length: Int = Qwen3ASRAudio.nSamples) -> MLXArray {
    let n = audio.shape[0]

    if n > length {
        // Truncate: take first `length` samples
        return audio[0 ..< length]
    } else if n < length {
        // Pad: append zeros to reach `length`
        let padding = MLXArray.zeros([length - n]).asType(audio.dtype)
        return MLX.concatenated([audio, padding])
    } else {
        return audio
    }
}

/// Compute log-mel spectrogram for Qwen3-ASR
///
/// This function converts raw audio waveform to log-mel spectrogram features
/// compatible with the Qwen3-ASR model. The output matches WhisperFeatureExtractor.
///
/// ## Processing Pipeline
/// 1. STFT with Hann window (400 samples, 160 hop)
/// 2. Power spectrum (magnitude squared)
/// 3. Mel filterbank projection (128 bins)
/// 4. Log scale with floor clipping
/// 5. Normalization to [-1, 1] range
///
/// ## PITFALL - Frame Count Compatibility
/// We drop the last STFT frame to match PyTorch's torch.stft(center=True) behavior.
/// This is critical: off-by-one frame count causes dimension mismatch in the model!
///
/// - Parameters:
///   - audio: Audio waveform, shape (T,) at 16kHz
///   - padding: Extra zero-padding samples (rarely needed)
/// - Returns: Log-mel spectrogram, shape (n_frames, 128)
public func logMelSpectrogram(
    audio: MLXArray,
    padding: Int = 0
) -> MLXArray {
    var audioArray = audio

    if padding > 0 {
        audioArray = MLX.padded(audioArray, widths: [IntOrPair((0, padding))])
    }

    // Use pre-computed Hann window (avoids ~2ms recomputation)
    let window = Qwen3ASRAudio.hannWindow

    // Compute STFT: waveform -> complex spectrogram
    let stftResult = stft(
        audioArray,
        window: window,
        nFft: Qwen3ASRAudio.nFft,
        hopLength: Qwen3ASRAudio.hopLength
    )

    // CRITICAL: Drop last frame to match WhisperFeatureExtractor / mlx-audio reference
    // (Both the upstream Whisper implementation and mlx-audio drop the final frame after STFT.)
    // For extremely short audio, STFT may produce only 1 frame; avoid slicing to an empty tensor.
    let freqs: MLXArray
    if stftResult.shape[0] > 1 {
        freqs = stftResult[0 ..< (stftResult.shape[0] - 1), 0...]
    } else {
        freqs = stftResult
    }

    // Power spectrum: |STFT|^2
    let magnitudes = MLX.pow(MLX.abs(freqs), 2)

    // Use pre-computed mel filterbank (avoids ~5ms recomputation)
    let filters = Qwen3ASRAudio.melFilterbank

    // Apply mel filterbank: (frames, freq_bins) @ (freq_bins, mels) -> (frames, mels)
    let melSpec = MLX.matmul(magnitudes, filters.T)

    // Log scale with floor clipping to prevent -inf
    var logSpec = MLX.log10(MLX.maximum(melSpec, MLXArray(1e-10)))

    // Dynamic range compression: clip to max - 8.0 (80dB range)
    // This prevents very quiet frames from dominating the normalization
    logSpec = MLX.maximum(logSpec, logSpec.max() - 8.0)

    // Normalize to approximately [-1, 1] range
    // The constants (4.0, 4.0) are from WhisperFeatureExtractor
    logSpec = (logSpec + 4.0) / 4.0

    return logSpec
}

// MARK: - Helper Functions

/// Create a Hann window
///
/// Note: Prefer using `Qwen3ASRAudio.hannWindow` for the pre-computed cached version.
/// This function is kept for reference and testing.
private func hanningWindow(length: Int) -> MLXArray {
    if length == 1 {
        return MLXArray([1.0])
    }

    let indices = (0 ..< length).map { Float($0) }
    let n = MLXArray(indices)
    let factor = 2.0 * Float.pi / Float(length - 1)
    return 0.5 * (1.0 - MLX.cos(n * factor))
}

/// Compute Short-Time Fourier Transform (STFT)
///
/// This implementation uses:
/// - Reflection padding (center=True equivalent)
/// - Efficient strided view for frame extraction (no copy)
/// - Real FFT for positive frequencies only
///
/// ## PITFALL - Frame Count
/// The output has one MORE frame than PyTorch's torch.stft with center=True.
/// Caller must drop the last frame for compatibility!
///
/// - Parameters:
///   - x: Input waveform, shape (samples,)
///   - window: Window function, shape (nFft,)
///   - nFft: FFT size (must match window length)
///   - hopLength: Samples between consecutive frames
/// - Returns: Complex spectrogram, shape (frames, nFft/2+1)
private func stft(
    _ x: MLXArray,
    window: MLXArray,
    nFft: Int,
    hopLength: Int
) -> MLXArray {
    // Center padding with reflection (mirrors torch.stft center=True)
    let padded = reflectPad(x, padding: nFft / 2)

    // Calculate number of frames
    let numFrames = 1 + (padded.shape[0] - nFft) / hopLength
    if numFrames <= 0 {
        fatalError("Input is too short for STFT with nFft=\(nFft)")
    }

    // Create overlapping frames using strided view (no memory copy!)
    // Each frame is `nFft` samples, stepping by `hopLength`
    let shape = [numFrames, nFft]
    let strides = [hopLength, 1]
    let frames = MLX.asStrided(padded, shape, strides: strides)

    // Apply window and compute real FFT
    // rfft returns only positive frequencies: nFft -> nFft/2+1 complex values
    let windowedFrames = frames * window
    let spec = MLX.rfft(windowedFrames)

    return spec
}

/// Reflect padding for 1D array
private func reflectPad(_ x: MLXArray, padding: Int) -> MLXArray {
    if padding == 0 {
        return x
    }

    let n = x.shape[0]
    if n == 0 {
        return MLXArray.zeros([2 * padding])
    }
    if n == 1 {
        return MLX.concatenated([
            MLXArray.full([padding], values: x[0]),
            x,
            MLXArray.full([padding], values: x[0]),
        ])
    }

    // Reflect at boundaries
    var prefix = reverseAlongAxis(x[1 ..< min(padding + 1, n)], axis: 0)
    var suffix = reverseAlongAxis(x[max(0, n - padding - 1) ..< (n - 1)], axis: 0)

    // Handle cases where array is shorter than padding
    while prefix.shape[0] < padding {
        let additional = min(padding - prefix.shape[0], n - 1)
        prefix = MLX.concatenated([reverseAlongAxis(x[1 ..< (additional + 1)], axis: 0), prefix])
    }

    while suffix.shape[0] < padding {
        let additional = min(padding - suffix.shape[0], n - 1)
        suffix = MLX.concatenated([suffix, reverseAlongAxis(x[(n - additional - 1) ..< (n - 1)], axis: 0)])
    }

    return MLX.concatenated([prefix[0 ..< padding], x, suffix[0 ..< padding]])
}

/// Reverse array along axis
private func reverseAlongAxis(_ x: MLXArray, axis: Int) -> MLXArray {
    let shape = x.shape
    let indices = MLXArray((0 ..< shape[axis]).reversed().map { Int32($0) })
    return x[indices]
}

/// Create mel filterbank matrix
///
/// Computes triangular mel filterbank following librosa/Slaney conventions.
/// This matches the WhisperFeatureExtractor implementation.
///
/// ## Mel Scale
/// Uses Slaney-style mel scale (linear below 1kHz, logarithmic above).
/// This is different from the HTK mel scale!
///
/// ## Slaney Normalization
/// Each filter is normalized by 2/(f_high - f_low) to give unit area.
/// This ensures energy is preserved across the frequency range.
///
/// Note: Prefer using `Qwen3ASRAudio.melFilterbank` for the pre-computed cached version.
///
/// - Parameters:
///   - sampleRate: Audio sample rate in Hz
///   - nFft: FFT size (determines frequency resolution)
///   - nMels: Number of mel frequency bins
///   - fMin: Minimum frequency in Hz (default 0)
///   - fMax: Maximum frequency in Hz (default Nyquist = sampleRate/2)
/// - Returns: Mel filterbank matrix, shape (nMels, nFft/2+1)
func computeMelFilters(
    sampleRate: Int,
    nFft: Int,
    nMels: Int,
    fMin: Float = 0.0,
    fMax: Float? = nil
) -> MLXArray {
    let actualFMax = fMax ?? Float(sampleRate) / 2.0

    // ─────────────────────────────────────────────────────────────────────────
    // Mel scale conversion (Slaney style, NOT HTK)
    // Below 1kHz: linear scale (mel = hz / (200/3))
    // Above 1kHz: logarithmic scale
    // ─────────────────────────────────────────────────────────────────────────
    func hzToMel(_ hz: Float) -> Float {
        let fSp: Float = 200.0 / 3.0        // Linear region slope
        let minLogHz: Float = 1000.0         // Transition point
        let minLogMel = minLogHz / fSp       // Mel value at transition
        let logstep: Float = log(6.4) / 27.0 // Log region step

        if hz >= minLogHz {
            return minLogMel + log(hz / minLogHz) / logstep
        } else {
            return hz / fSp
        }
    }

    func melToHz(_ mel: Float) -> Float {
        let fSp: Float = 200.0 / 3.0
        let minLogHz: Float = 1000.0
        let minLogMel = minLogHz / fSp
        let logstep: Float = log(6.4) / 27.0

        if mel >= minLogMel {
            return minLogHz * exp(logstep * (mel - minLogMel))
        } else {
            return fSp * mel
        }
    }

    // Create nMels+2 evenly spaced points in mel scale
    // +2 because we need left and right edges for first and last filters
    let melMin = hzToMel(fMin)
    let melMax = hzToMel(actualFMax)
    let melPoints = (0 ... nMels + 1).map { i in
        melToHz(melMin + Float(i) * (melMax - melMin) / Float(nMels + 1))
    }

    // FFT bin center frequencies
    let fftFreqs = (0 ..< (nFft / 2 + 1)).map { i in
        Float(i) * Float(sampleRate) / Float(nFft)
    }

    // Build triangular filterbank
    var filterbank = [[Float]](repeating: [Float](repeating: 0, count: nFft / 2 + 1), count: nMels)

    for m in 0 ..< nMels {
        let fLeft = melPoints[m]      // Left edge of filter
        let fCenter = melPoints[m + 1] // Center (peak) of filter
        let fRight = melPoints[m + 2]  // Right edge of filter

        for k in 0 ..< (nFft / 2 + 1) {
            let freq = fftFreqs[k]

            // Rising edge: fLeft to fCenter
            if freq >= fLeft, freq <= fCenter {
                filterbank[m][k] = (freq - fLeft) / (fCenter - fLeft)
            }
            // Falling edge: fCenter to fRight
            else if freq > fCenter, freq <= fRight {
                filterbank[m][k] = (fRight - freq) / (fRight - fCenter)
            }
            // Outside filter: 0 (already initialized)
        }

        // Slaney normalization: scale filter to have unit area
        // This ensures consistent energy across frequency range
        let enorm = 2.0 / (melPoints[m + 2] - melPoints[m])
        for k in 0 ..< (nFft / 2 + 1) {
            filterbank[m][k] *= enorm
        }
    }

    return MLXArray(filterbank.flatMap { $0 }).reshaped([nMels, nFft / 2 + 1])
}

// MARK: - Errors

/// Errors that can occur during Qwen3-ASR operations
public enum Qwen3ASRError: Error, LocalizedError {
    /// Audio file could not be loaded or converted
    /// Common causes: file not found, unsupported format, corrupt file
    case audioLoadFailed(String)

    /// Model weights or config could not be loaded
    /// Common causes: missing files, incompatible quantization, corrupt weights
    case modelLoadFailed(String)

    /// Tokenizer files could not be loaded
    /// Common causes: missing vocab.json or merges.txt
    case tokenizerLoadFailed(String)

    /// Token generation failed during transcription
    /// Common causes: out of memory, invalid audio features
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .audioLoadFailed(message):
            return "Audio load failed: \(message)"
        case let .modelLoadFailed(message):
            return "Model load failed: \(message)"
        case let .tokenizerLoadFailed(message):
            return "Tokenizer load failed: \(message)"
        case let .generationFailed(message):
            return "Generation failed: \(message)"
        }
    }
}
