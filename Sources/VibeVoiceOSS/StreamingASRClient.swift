import Foundation

/// Result-only Streaming adapter: PCM appends are ignored; `finish` is unused.
/// Used when AppState already holds the WAV and calls TranscriptionClient directly.
struct NullPCMStreamingClient: StreamingASRClient {
    func appendPCM(_ frame: Data) async throws {}
    func finish() async throws -> String {
        throw TranscriptionError.invalidResponse
    }
    func cancel() async {}
}

/// Duplex WebSocket client. Protocol (JSON text frames):
/// Client → `{ "type":"audio","pcm16_b64":"..." }` / `{ "type":"commit" }` / `{ "type":"end" }`
/// Server → `{ "type":"partial"|"stable"|"final","text":"..." }` / `{ "type":"error","message":"..." }`
actor WebSocketStreamingASRClient: StreamingASRClient {
    private let url: URL
    private let apiKey: String
    private let onEvent: StreamingASRPartialHandler
    private var task: URLSessionWebSocketTask?
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var finalText: String?
    private var closed = false
    private let session: URLSession

    init(url: URL, apiKey: String, onEvent: @escaping StreamingASRPartialHandler) {
        self.url = url
        self.apiKey = apiKey
        self.onEvent = onEvent
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func connect() async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let socket = session.webSocketTask(with: request)
        task = socket
        socket.resume()
        try await sendJSON(["type": "session.start"])
        receiveLoop()
    }

    func appendPCM(_ frame: Data) async throws {
        guard !closed, task != nil else { return }
        let b64 = frame.base64EncodedString()
        try await sendJSON(["type": "audio", "pcm16_b64": b64])
    }

    func finish() async throws -> String {
        try await sendJSON(["type": "commit"])
        try await sendJSON(["type": "end"])
        return try await withCheckedThrowingContinuation { continuation in
            if let finalText {
                continuation.resume(returning: finalText)
                return
            }
            finalContinuation = continuation
        }
    }

    func cancel() async {
        closed = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if let continuation = finalContinuation {
            finalContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            throw TranscriptionError.invalidResponse
        }
        try await task.send(.string(text))
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { await self?.handleReceive(result) }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>) async {
        switch result {
        case .failure(let error):
            if !closed {
                onEvent(.error(error.localizedDescription))
                if let continuation = finalContinuation {
                    finalContinuation = nil
                    continuation.resume(throwing: error)
                }
            }
        case .success(let message):
            let text: String?
            switch message {
            case .string(let string): text = string
            case .data(let data): text = String(data: data, encoding: .utf8)
            @unknown default: text = nil
            }
            if let text { parseServerMessage(text) }
            if !closed { receiveLoop() }
        }
    }

    private func parseServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        let payload = (json["text"] as? String) ?? ""
        switch type {
        case "partial":
            onEvent(.partial(payload))
        case "stable":
            onEvent(.stable(payload))
        case "final":
            finalText = payload
            onEvent(.final(payload))
            onEvent(.done)
            if let continuation = finalContinuation {
                finalContinuation = nil
                continuation.resume(returning: payload)
            }
        case "error":
            let message = (json["message"] as? String) ?? "Streaming ASR 错误"
            onEvent(.error(message))
            if let continuation = finalContinuation {
                finalContinuation = nil
                continuation.resume(throwing: TranscriptionError.server(status: 500, message: message))
            }
        default:
            break
        }
    }
}

/// Pseudo-Streaming with commit + live tail:
/// - `stable` grows from older audio segments (won't flicker away)
/// - `partial` is only the still-open trailing window (revisable as you speak)
actor OverlappingWindowStreamingASRClient: StreamingASRClient {
    private let client: TranscriptionClient
    private let configuration: TranscriptionConfiguration
    private let onEvent: StreamingASRPartialHandler

    private let bytesPerSecond = 16_000 * 2
    /// How often we wake up to mark audio dirty.
    private let pollNanoseconds: UInt64
    /// Max uncommitted live audio kept for revisable recognition.
    private let liveWindowBytes: Int
    /// Leave this much audio in the live region when committing.
    private let liveKeepBytes: Int

    private var pcm16: Data = Data()
    private var committedBytes = 0
    private var tickTask: Task<Void, Never>?
    private var cancelled = false
    private var inflight = false
    private var dirty = false
    private var latestLive = ""

    init(
        client: TranscriptionClient = TranscriptionClient(),
        configuration: TranscriptionConfiguration,
        liveWindowSeconds: Double = 2.8,
        liveKeepSeconds: Double = 1.1,
        pollMs: UInt64 = 280,
        onEvent: @escaping StreamingASRPartialHandler
    ) {
        self.client = client
        self.configuration = configuration
        self.liveWindowBytes = Int(liveWindowSeconds * Double(16_000 * 2))
        self.liveKeepBytes = Int(liveKeepSeconds * Double(16_000 * 2))
        self.pollNanoseconds = pollMs * 1_000_000
        self.onEvent = onEvent
    }

    func start() {
        cancelled = false
        committedBytes = 0
        latestLive = ""
        dirty = false
        tickTask?.cancel()
        tickTask = Task { await self.tickLoop() }
    }

    func appendPCM(_ frame: Data) async throws {
        guard !cancelled else { return }
        pcm16.append(frame)
        // Bound memory (~45 s).
        // Important: do NOT use removeFirst(_:) here — it leaves Data.startIndex ≠ 0,
        // and later 0-based subdata(in:) traps (SIGTRAP) once the buffer has wrapped.
        let maxBytes = bytesPerSecond * 45
        if pcm16.count > maxBytes {
            let drop = pcm16.count - maxBytes
            pcm16 = Data(pcm16.suffix(maxBytes))
            committedBytes = max(0, committedBytes - drop)
        }
        dirty = true
        await pumpIfNeeded()
    }

    func finish() async throws -> String {
        tickTask?.cancel()
        tickTask = nil
        // One last live refresh, then full-pass final.
        dirty = true
        await recognize(force: true)
        let wav = wavFromPCM16(pcm16)
        let text = try await client.transcribe(
            wav: wav,
            configuration: configuration,
            streamResults: false,
            onEvent: nil
        )
        latestLive = text
        onEvent(.final(text))
        onEvent(.done)
        return text
    }

    func cancel() async {
        cancelled = true
        tickTask?.cancel()
        tickTask = nil
    }

    private func tickLoop() async {
        while !Task.isCancelled && !cancelled {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
            dirty = true
            await pumpIfNeeded()
        }
    }

    private func pumpIfNeeded() async {
        guard !cancelled, dirty, !inflight else { return }
        dirty = false
        inflight = true
        defer {
            inflight = false
            if dirty, !cancelled {
                Task { await self.pumpIfNeeded() }
            }
        }
        await recognize(force: false)
    }

    private func recognize(force: Bool) async {
        guard !cancelled else { return }
        // Need a little audio before first decode.
        let minBytes = bytesPerSecond * 28 / 100 // ~0.28 s
        guard pcm16.count - committedBytes >= minBytes || (force && pcm16.count > 0) else { return }

        // Commit older audio when the live region grows beyond the window.
        while pcm16.count - committedBytes > liveWindowBytes, !cancelled {
            let commitTo = max(committedBytes, pcm16.count - liveKeepBytes)
            guard commitTo > committedBytes + minBytes else { break }
            let ok = await commitSegment(from: committedBytes, to: commitTo)
            if ok {
                committedBytes = commitTo
                latestLive = ""
                onEvent(.partial(""))
            } else {
                break
            }
        }

        let liveFrom = min(committedBytes, pcm16.count)
        guard let liveSlice = copyPCM(from: liveFrom, to: pcm16.count) else { return }
        guard liveSlice.count >= minBytes || force else { return }

        do {
            let text = try await transcribePCM(liveSlice)
            guard !cancelled, !text.isEmpty else { return }
            latestLive = text
            onEvent(.partial(text))
        } catch is CancellationError {
            return
        } catch let error as TranscriptionError {
            if case .emptyText = error { return }
            if case let .server(status, _) = error, status == 401 || status == 403 {
                onEvent(.error("转写需要 API Key：请在设置 → 语音识别中填写后重试"))
            }
        } catch {
            return
        }
    }

    @discardableResult
    private func commitSegment(from: Int, to: Int) async -> Bool {
        // Copy before any await so actor reentrancy (appendPCM truncating pcm16) cannot
        // invalidate indices mid-flight.
        guard let slice = copyPCM(from: from, to: to) else { return false }
        do {
            let text = try await transcribePCM(slice)
            guard !cancelled, !text.isEmpty else { return false }
            onEvent(.stable(text))
            return true
        } catch {
            return false
        }
    }

    /// 0-based offsets into the logical PCM buffer, safe even if Data.startIndex ≠ 0.
    private func copyPCM(from: Int, to: Int) -> Data? {
        guard from >= 0, to > from, to <= pcm16.count else { return nil }
        let start = pcm16.index(pcm16.startIndex, offsetBy: from)
        let end = pcm16.index(pcm16.startIndex, offsetBy: to)
        return Data(pcm16[start..<end])
    }

    private func transcribePCM(_ pcm: Data) async throws -> String {
        let wav = wavFromPCM16(pcm)
        let text = try await client.transcribe(
            wav: wav,
            configuration: configuration,
            streamResults: false,
            onEvent: nil
        )
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.looksLikePromptHallucination(trimmed, prompt: configuration.prompt) {
            return ""
        }
        return trimmed
    }

    /// ASR models often echo the hotspot `prompt` during silence / noise.
    private static func looksLikePromptHallucination(_ text: String, prompt: String) -> Bool {
        let compactText = compactASRToken(text)
        guard !compactText.isEmpty else { return true }
        let compactPrompt = compactASRToken(prompt)
        if !compactPrompt.isEmpty {
            let stripped = compactText.replacingOccurrences(of: compactPrompt, with: "")
            if stripped.isEmpty { return true }
        }
        // Known placeholder echoes even when the stored prompt was already cleared.
        let junkRoots = ["localasrmacos", "asrmacos", "qwen3asromlxswiftmacos"]
        for root in junkRoots {
            let stripped = compactText.replacingOccurrences(of: root, with: "")
            if stripped.isEmpty { return true }
        }
        return false
    }

    private static func compactASRToken(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "，", with: ",")
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func wavFromPCM16(_ pcm: Data) -> Data {
        var samples = [Float](repeating: 0, count: pcm.count / 2)
        pcm.withUnsafeBytes { raw in
            let ints = raw.bindMemory(to: Int16.self)
            for index in 0..<samples.count {
                samples[index] = Float(Int16(littleEndian: ints[index])) / Float(Int16.max)
            }
        }
        return WAVEncoder.encode(samples: samples, inputSampleRate: Double(WAVEncoder.outputSampleRate))
    }
}
