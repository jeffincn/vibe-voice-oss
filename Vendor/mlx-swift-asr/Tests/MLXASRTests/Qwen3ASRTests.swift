// Copyright © 2025 OnType
// Qwen3-ASR Tests

import Foundation
import MLX
import Testing

@testable import MLXASR

@Suite("Qwen3-ASR Tests")
struct Qwen3ASRTests {
    // Path to the model directory
    static let modelDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("server/models/Qwen3-ASR-0.6B-6bit")

    // Path to test audio
    static var testAudioPath: URL {
        Bundle.module.url(forResource: "test_audio", withExtension: "wav", subdirectory: "Resources")
            ?? URL(fileURLWithPath: "/Users/dio/Projects/OnType/macos/Tests/OnTypeMLXTests/Resources/test_audio.wav")
    }

    @Test("Load config from model directory")
    func testLoadConfig() throws {
        let config = try Qwen3ASRConfig.load(from: Self.modelDirectory)

        #expect(config.audioConfig.numMelBins == 128)
        #expect(config.audioConfig.encoderLayers > 0)
        #expect(config.textConfig.vocabSize > 0)
        #expect(config.audioTokenId > 0)
    }

    @Test("Create model from config")
    func testCreateModel() throws {
        let config = try Qwen3ASRConfig.load(from: Self.modelDirectory)
        let model = Qwen3ASRModel(config: config)

        #expect(model.sampleRate == 16000)
        #expect(model.numLayers == config.textConfig.numHiddenLayers)
    }

    @Test("Load audio file")
    func testLoadAudio() throws {
        let audio = try loadAudio(from: Self.testAudioPath)

        // Audio should be non-empty
        #expect(audio.count > 0)

        // Audio should be at 16kHz, ~7.5 seconds = ~120000 samples
        #expect(audio.count > 80000)
        #expect(audio.count < 150000)
    }

    @Test("Compute mel spectrogram")
    func testMelSpectrogram() throws {
        let audio = try loadAudio(from: Self.testAudioPath)
        let audioArray = MLXArray(audio)

        let melSpec = logMelSpectrogram(audio: audioArray)
        eval(melSpec)

        // Shape should be (n_frames, n_mels)
        #expect(melSpec.ndim == 2)
        #expect(melSpec.shape[1] == 128) // n_mels
        #expect(melSpec.shape[0] > 0) // n_frames
    }

    @Test("Load full model and transcribe")
    func testTranscribe() async throws {
        // Load STT
        let stt = try await Qwen3ASRSTT.load(from: Self.modelDirectory)

        // Load and transcribe audio
        let result = try await stt.transcribe(file: Self.testAudioPath)

        print("Transcription: \(result.text)")
        print("Processing time: \(result.processingTime)s")
        print("Audio duration: \(result.audioDuration)s")
        print("Real-time factor: \(result.processingTime / result.audioDuration)")

        // Transcription should be non-empty
        #expect(!result.text.isEmpty)

        // Should contain some expected words from the audio
        // The audio says: "The examination and testimony of the experts enabled the commission
        // to conclude that five shots may have been fired"
        let text = result.text.lowercased()
        let containsExpectedWord = text.contains("examination")
            || text.contains("testimony")
            || text.contains("experts")
            || text.contains("commission")
            || text.contains("shots")
            || text.contains("fired")
        #expect(containsExpectedWord)
    }
}

// MARK: - Batch Transcription Tests with 1.7B Model

@Suite("Qwen3-ASR 0.6B Benchmark")
struct Qwen3ASRBenchmark {
    // Path to 0.6B model for benchmark comparison with Python
    static let modelDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("server/models/Qwen3-ASR-0.6B-6bit")

    // Benchmark files (same as Python)
    static let benchmarkFiles = [
        "trump_0.wav",
        "obama_prompt.wav",
        "qwen-tts-08c61feb.wav",
        "ssds_prompt.wav",
    ]

    static let samplesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("server/samples")

    @Test("Warmup Comparison")
    func testWarmupComparison() async throws {
        let fileURL = Self.samplesDirectory.appendingPathComponent("trump_0.wav")

        print("\n" + String(repeating: "=", count: 60))
        print("WARMUP COMPARISON TEST")
        print(String(repeating: "=", count: 60))

        // Test 1: Without warmup
        print("\n--- WITHOUT Warmup ---")
        let loadStart1 = CFAbsoluteTimeGetCurrent()
        let stt1 = try await Qwen3ASRSTT.load(from: Self.modelDirectory)
        let loadTime1 = CFAbsoluteTimeGetCurrent() - loadStart1
        print("Load time: \(String(format: "%.2f", loadTime1))s")

        let result1 = try await stt1.transcribe(file: fileURL)
        let rtf1 = result1.processingTime / result1.audioDuration
        print("First request: \(String(format: "%.2f", result1.processingTime))s | RTF: \(String(format: "%.3f", rtf1)) | \(String(format: "%.1f", 1/rtf1))x real-time")

        // Test 2: With warmup (new model instance to avoid cache sharing)
        print("\n--- WITH Warmup ---")
        let loadStart2 = CFAbsoluteTimeGetCurrent()
        let stt2 = try await Qwen3ASRSTT.loadWithWarmup(from: Self.modelDirectory)
        let loadTime2 = CFAbsoluteTimeGetCurrent() - loadStart2
        print("Load + Warmup time: \(String(format: "%.2f", loadTime2))s")

        let result2 = try await stt2.transcribe(file: fileURL)
        let rtf2 = result2.processingTime / result2.audioDuration
        print("First request: \(String(format: "%.2f", result2.processingTime))s | RTF: \(String(format: "%.3f", rtf2)) | \(String(format: "%.1f", 1/rtf2))x real-time")

        // Summary
        print("\n--- Summary ---")
        print("Without warmup first request: \(String(format: "%.1f", 1/rtf1))x real-time")
        print("With warmup first request:    \(String(format: "%.1f", 1/rtf2))x real-time")
        print("Improvement: \(String(format: "%.1f", (1/rtf2)/(1/rtf1)))x faster")
        print(String(repeating: "=", count: 60))
    }

    @Test("Benchmark 0.6B model (compare with Python)")
    func testBenchmark() async throws {
        print("\n" + String(repeating: "=", count: 60))
        print("Swift OnTypeMLX Performance (Qwen3-ASR-0.6B-6bit)")
        print(String(repeating: "=", count: 60))

        // Load model
        let loadStart = CFAbsoluteTimeGetCurrent()
        let stt = try await Qwen3ASRSTT.load(from: Self.modelDirectory)
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        print("Model loaded in \(String(format: "%.2f", loadTime))s")
        print()

        var totalAudioDuration: Double = 0
        var totalProcessingTime: Double = 0

        for fileName in Self.benchmarkFiles {
            let fileURL = Self.samplesDirectory.appendingPathComponent(fileName)

            let result = try await stt.transcribe(file: fileURL)

            let rtf = result.processingTime / result.audioDuration
            totalAudioDuration += result.audioDuration
            totalProcessingTime += result.processingTime

            print("\(fileName)")
            print("  Duration: \(String(format: "%.2f", result.audioDuration))s | Time: \(String(format: "%.2f", result.processingTime))s | RTF: \(String(format: "%.3f", rtf))")
            let textDisplay = result.text.count > 80 ? String(result.text.prefix(80)) + "..." : result.text
            print("  Text: \(textDisplay)")
            print()
        }

        print(String(repeating: "=", count: 60))
        print("Total Audio: \(String(format: "%.2f", totalAudioDuration))s | Total Time: \(String(format: "%.2f", totalProcessingTime))s")
        print("Average RTF: \(String(format: "%.3f", totalProcessingTime / totalAudioDuration))")
        print("Speedup: \(String(format: "%.1f", totalAudioDuration / totalProcessingTime))x real-time")
        print(String(repeating: "=", count: 60))

        #expect(totalProcessingTime < totalAudioDuration * 2) // At least 0.5x real-time
    }
}

@Suite("Qwen3-ASR 1.7B Benchmark")
struct Qwen3ASR17BBenchmark {
    // Path to 1.7B model
    static let modelDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("server/models/Qwen3-ASR-1.7B-6bit")

    // Same benchmark files as 0.6B (for fair comparison with Python)
    static let benchmarkFiles = [
        "trump_0.wav",
        "obama_prompt.wav",
        "qwen-tts-08c61feb.wav",
        "ssds_prompt.wav",
    ]

    static let samplesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("server/samples")

    @Test("Benchmark 1.7B model (compare with Python)")
    func testBenchmark() async throws {
        print("\n" + String(repeating: "=", count: 60))
        print("Swift OnTypeMLX Performance (Qwen3-ASR-1.7B-6bit)")
        print(String(repeating: "=", count: 60))

        let loadStart = CFAbsoluteTimeGetCurrent()
        let stt = try await Qwen3ASRSTT.load(from: Self.modelDirectory)
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        print("Model loaded in \(String(format: "%.2f", loadTime))s")
        print()

        var totalAudioDuration: Double = 0
        var totalProcessingTime: Double = 0

        for fileName in Self.benchmarkFiles {
            let fileURL = Self.samplesDirectory.appendingPathComponent(fileName)
            let result = try await stt.transcribe(file: fileURL)

            let rtf = result.processingTime / result.audioDuration
            totalAudioDuration += result.audioDuration
            totalProcessingTime += result.processingTime

            print("\(fileName)")
            print("  Duration: \(String(format: "%.2f", result.audioDuration))s | Time: \(String(format: "%.2f", result.processingTime))s | RTF: \(String(format: "%.3f", rtf))")
        }

        print()
        print(String(repeating: "=", count: 60))
        print("Total Audio: \(String(format: "%.2f", totalAudioDuration))s | Total Time: \(String(format: "%.2f", totalProcessingTime))s")
        print("Average RTF: \(String(format: "%.3f", totalProcessingTime / totalAudioDuration))")
        print("Speedup: \(String(format: "%.1f", totalAudioDuration / totalProcessingTime))x real-time")
        print(String(repeating: "=", count: 60))
    }
}

@Suite("Qwen3-ASR 1.7B Batch Tests")
struct Qwen3ASRBatchTests {
    // Path to 1.7B model
    static let modelDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("server/models/Qwen3-ASR-1.7B-6bit")

    // Path to samples directory
    static let samplesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("server/samples")

    @Test("Batch transcribe all samples with 1.7B model")
    func testBatchTranscribe() async throws {
        print("\n" + String(repeating: "=", count: 80))
        print("Qwen3-ASR 1.7B-6bit Batch Transcription Test")
        print(String(repeating: "=", count: 80))

        // Load model
        print("\nLoading model from: \(Self.modelDirectory.path)")
        let loadStart = CFAbsoluteTimeGetCurrent()
        let stt = try await Qwen3ASRSTT.load(from: Self.modelDirectory)
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        print("Model loaded in \(String(format: "%.2f", loadTime))s")

        // Get all wav files
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: Self.samplesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        print("\nFound \(files.count) audio files")
        print(String(repeating: "-", count: 80))

        var totalAudioDuration: Double = 0
        var totalProcessingTime: Double = 0
        var successCount = 0
        var failCount = 0

        var results: [(file: String, duration: Double, time: Double, rtf: Double, text: String)] = []

        for (index, file) in files.enumerated() {
            let fileName = file.lastPathComponent.removingPercentEncoding ?? file.lastPathComponent

            do {
                let result = try await stt.transcribe(file: file)

                let rtf = result.processingTime / result.audioDuration
                totalAudioDuration += result.audioDuration
                totalProcessingTime += result.processingTime
                successCount += 1

                results.append((
                    file: fileName,
                    duration: result.audioDuration,
                    time: result.processingTime,
                    rtf: rtf,
                    text: result.text
                ))

                print("\n[\(index + 1)/\(files.count)] \(fileName)")
                print("  Duration: \(String(format: "%.2f", result.audioDuration))s | Time: \(String(format: "%.2f", result.processingTime))s | RTF: \(String(format: "%.3f", rtf))")
                print("  Text: \(result.text)")

            } catch {
                failCount += 1
                print("\n[\(index + 1)/\(files.count)] \(fileName)")
                print("  ERROR: \(error)")
            }
        }

        // Summary
        print("\n" + String(repeating: "=", count: 80))
        print("SUMMARY")
        print(String(repeating: "=", count: 80))
        print("Model: Qwen3-ASR-1.7B-6bit")
        print("Model Load Time: \(String(format: "%.2f", loadTime))s")
        print("Files Processed: \(successCount)/\(files.count) (failed: \(failCount))")
        print("Total Audio Duration: \(String(format: "%.2f", totalAudioDuration))s (\(String(format: "%.1f", totalAudioDuration / 60))min)")
        print("Total Processing Time: \(String(format: "%.2f", totalProcessingTime))s (\(String(format: "%.1f", totalProcessingTime / 60))min)")
        print("Average RTF: \(String(format: "%.3f", totalProcessingTime / totalAudioDuration))")
        print("Speedup: \(String(format: "%.1f", totalAudioDuration / totalProcessingTime))x real-time")
        print(String(repeating: "=", count: 80))

        #expect(successCount > 0)
    }
}
