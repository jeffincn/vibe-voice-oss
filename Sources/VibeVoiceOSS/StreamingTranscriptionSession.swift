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

    /// Open a local-only streaming session for integrated ASR (no WebSocket).
    /// Uses wider windows and slower polling since local inference is heavier.
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

        let window = OverlappingWindowStreamingASRClient(
            configuration: configuration,
            liveWindowSeconds: 6.0,
            liveKeepSeconds: 2.5,
            pollMs: 2500,
            onEvent: handler
        )
        await window.start()
        windowClient = window
        client = window
        backend = .overlappingWindow
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
