import Foundation

/// Orchestrates a live Streaming ASR session: PCM in, accumulator events out.
@MainActor
final class StreamingTranscriptionSession {
    enum Backend: String {
        case webSocket
        case overlappingWindow
    }

    private(set) var accumulator = TranscriptAccumulator()
    private(set) var backend: Backend?
    private(set) var isOpen = false

    private var client: (any StreamingASRClient)?
    private var webSocketClient: WebSocketStreamingASRClient?
    private var windowClient: OverlappingWindowStreamingASRClient?
    private let onUpdate: (TranscriptAccumulator) -> Void
    private let onFirstPartial: () -> Void
    private let onUsage: (TokenUsage) -> Void
    private var sawPartial = false
    private var pendingPCM: [Data] = []
    private var pcmDrainTask: Task<Void, Never>?

    init(
        onUpdate: @escaping (TranscriptAccumulator) -> Void,
        onFirstPartial: @escaping () -> Void = {},
        onUsage: @escaping (TokenUsage) -> Void = { _ in }
    ) {
        self.onUpdate = onUpdate
        self.onFirstPartial = onFirstPartial
        self.onUsage = onUsage
    }

    func open(
        configuration: TranscriptionConfiguration,
        streamingWSURL: URL?
    ) async {
        closeClients()
        accumulator.reset()
        sawPartial = false
        pendingPCM.removeAll(keepingCapacity: false)
        isOpen = true
        onUpdate(accumulator)

        let handler: StreamingASRPartialHandler = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }

        if let streamingWSURL {
            let ws = WebSocketStreamingASRClient(
                url: streamingWSURL,
                apiKey: configuration.apiKey,
                onEvent: handler
            )
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await ws.connect() }
                    group.addTask {
                        try await Task.sleep(for: .milliseconds(1_200))
                        throw TranscriptionError.timedOut
                    }
                    _ = try await group.next()
                    group.cancelAll()
                }
                webSocketClient = ws
                client = ws
                backend = .webSocket
                return
            } catch {
                await ws.cancel()
            }
        }

        let window = OverlappingWindowStreamingASRClient(
            configuration: configuration,
            onEvent: handler
        )
        await window.start()
        windowClient = window
        client = window
        backend = .overlappingWindow
    }

    /// The fast model used for live streaming captions during recording.
    /// The full-quality model is only used for the final transcription after recording stops.
    nonisolated static let streamingModel = "base"

    /// Open a local-only streaming session for integrated ASR (no WebSocket).
    /// Uses a lightweight model (base) for fast live captions. The configured
    /// full-quality model is used for the final batch transcription after
    /// recording stops — the dual-model approach gives responsive partials
    /// without sacrificing final accuracy.
    func openLocal(configuration: TranscriptionConfiguration) async {
        closeClients()
        accumulator.reset()
        sawPartial = false
        pendingPCM.removeAll(keepingCapacity: false)
        isOpen = true
        onUpdate(accumulator)

        let handler: StreamingASRPartialHandler = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }

        // Use a fast model for live streaming (base/tiny), regardless of
        // the configured production model. Qwen3 uses its own model directly.
        let streamConfig: TranscriptionConfiguration
        if configuration.integratedEngine == .whisperMLX {
            streamConfig = Self.streamingConfiguration(from: configuration)
        } else {
            streamConfig = configuration
        }

        let params = Self.localStreamingParams(for: streamConfig)
        let window = OverlappingWindowStreamingASRClient(
            configuration: streamConfig,
            liveWindowSeconds: params.window,
            liveKeepSeconds: params.keep,
            pollMs: params.poll,
            onEvent: handler
        )
        await window.start()
        windowClient = window
        client = window
        backend = .overlappingWindow
    }

    /// Build a lighter config for streaming by substituting a fast model.
    private static func streamingConfiguration(
        from config: TranscriptionConfiguration
    ) -> TranscriptionConfiguration {
        let target = config.whisperKitModel.lowercased()
        // If the user already configured a lightweight model, keep it.
        if target.contains("tiny") || target.contains("base") {
            return config
        }
        return TranscriptionConfiguration(
            backend: config.backend,
            integratedEngine: config.integratedEngine,
            integratedModelPath: config.integratedModelPath,
            qwenModelRepo: config.qwenModelRepo,
            whisperKitModel: streamingModel,
            endpoint: config.endpoint,
            model: config.model,
            language: config.language,
            prompt: config.prompt,
            apiKey: config.apiKey
        )
    }

    private struct LocalStreamingParams {
        let window: Double
        let keep: Double
        let poll: UInt64
    }

    /// Adaptive parameters based on the streaming model weight class.
    private static func localStreamingParams(for config: TranscriptionConfiguration) -> LocalStreamingParams {
        let model = config.whisperKitModel.lowercased()
        if config.integratedEngine == .qwen3MLX {
            return LocalStreamingParams(window: 3.5, keep: 1.2, poll: 1200)
        }
        if model.contains("tiny") {
            return LocalStreamingParams(window: 2.5, keep: 0.8, poll: 600)
        }
        // base (default streaming model) or small
        return LocalStreamingParams(window: 3.0, keep: 1.0, poll: 800)
    }

    func appendPCM(_ frame: Data) {
        guard isOpen, client != nil else { return }
        pendingPCM.append(frame)
        guard pcmDrainTask == nil else { return }
        pcmDrainTask = Task { [weak self] in
            await self?.drainPendingPCM()
        }
    }

    func finish() async throws -> String {
        guard isOpen, let client else {
            throw TranscriptionError.invalidResponse
        }
        if let pcmDrainTask {
            await pcmDrainTask.value
        }
        let leftover = pendingPCM
        pendingPCM.removeAll(keepingCapacity: false)
        for frame in leftover {
            try? await client.appendPCM(frame)
        }
        isOpen = false
        let text = try await client.finish()
        let finalized = accumulator.isFinalized ? accumulator.displayText : accumulator.applyFinal(text)
        onUpdate(accumulator)
        await client.cancel()
        clearClientRefs()
        return finalized
    }

    func cancel() {
        isOpen = false
        pendingPCM.removeAll(keepingCapacity: false)
        pcmDrainTask?.cancel()
        pcmDrainTask = nil
        Task {
            await client?.cancel()
            await MainActor.run { self.clearClientRefs() }
        }
    }

    private func drainPendingPCM() async {
        while isOpen, let client {
            let batch = pendingPCM
            pendingPCM.removeAll(keepingCapacity: true)
            if batch.isEmpty { break }
            for frame in batch {
                if Task.isCancelled || !isOpen { break }
                try? await client.appendPCM(frame)
            }
        }
        pcmDrainTask = nil
        // Frames may have arrived after the empty check but before clearing the task ref.
        if isOpen, client != nil, !pendingPCM.isEmpty, pcmDrainTask == nil {
            pcmDrainTask = Task { [weak self] in
                await self?.drainPendingPCM()
            }
        }
    }

    private func handle(_ event: StreamingASREvent) {
        switch event {
        case let .partial(text):
            accumulator.applyPartial(text)
            notePartial()
        case let .stable(text):
            accumulator.applyStable(text)
            notePartial()
        case let .final(text):
            accumulator.applyFinal(text)
            notePartial()
        case let .error(message):
            if accumulator.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                accumulator.applyPartial(message)
            }
        case let .usage(usage):
            onUsage(usage)
        case .done:
            break
        }
        onUpdate(accumulator)
    }

    private func notePartial() {
        guard !sawPartial, accumulator.hasContent else { return }
        sawPartial = true
        onFirstPartial()
    }

    private func closeClients() {
        cancel()
    }

    private func clearClientRefs() {
        client = nil
        webSocketClient = nil
        windowClient = nil
        backend = nil
        pendingPCM.removeAll(keepingCapacity: false)
        pcmDrainTask = nil
    }
}
