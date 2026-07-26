import Foundation

struct TranscriptionConfiguration: Sendable {
    let backend: ASRBackend
    let integratedEngine: IntegratedASREngine
    let integratedModelPath: String
    let qwenModelRepo: String
    let whisperKitModel: String
    let endpoint: String
    let model: String
    let language: String
    let prompt: String
    let apiKey: String
    /// Optional Hugging Face endpoint override (e.g. https://hf-mirror.com).
    /// Empty means the default https://huggingface.co.
    var hfEndpoint: String = ""

    /// Normalized HF endpoint, or nil when the default should be used.
    var normalizedHFEndpoint: String? {
        var trimmed = hfEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        while trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()), url.host != nil else {
            return nil
        }
        // Weights fetched from this mirror are loaded into the process, so anyone
        // able to tamper with the transfer chooses what the app runs. Plain HTTP is
        // only tolerable on loopback.
        guard !EndpointSecurity.isCleartextRemote(url) else { return nil }
        return trimmed
    }
}

enum TranscriptionError: LocalizedError {
    case invalidEndpoint
    case server(status: Int, message: String)
    case invalidResponse
    case emptyText
    case timedOut
    case localTimedOut(seconds: Int)
    case localRuntime(String)
    case insecureEndpoint

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: L10n.t(.errASRInvalidEndpoint)
        case let .server(status, message): L10n.t(.errASRServer, status, message)
        case .invalidResponse: L10n.t(.errASRInvalidResponse)
        case .emptyText: L10n.t(.errASREmptyText)
        case .timedOut: L10n.t(.errASRTimedOut)
        case let .localTimedOut(seconds): L10n.t(.errASRLocalTimedOut, seconds / 60)
        case let .localRuntime(message): L10n.t(.errASRLocalRuntime, message)
        case .insecureEndpoint: L10n.t(.errInsecureEndpoint)
        }
    }
}

struct TranscriptionClient: Sendable {
    private struct Response: Decodable { let text: String }

    func transcribe(
        wav: Data,
        configuration: TranscriptionConfiguration,
        onUsage: (@Sendable (TokenUsage) -> Void)? = nil
    ) async throws -> String {
        try await transcribe(
            wav: wav,
            configuration: configuration,
            streamResults: false,
            onEvent: nil,
            onUsage: onUsage
        )
    }

    /// Transcribe a complete WAV. When `streamResults` is true, requests `stream=true` and
    /// emits partial deltas if the server replies with SSE; otherwise falls back to JSON.
    func transcribe(
        wav: Data,
        configuration: TranscriptionConfiguration,
        streamResults: Bool,
        onEvent: StreamingASRPartialHandler?,
        onUsage: (@Sendable (TokenUsage) -> Void)? = nil
    ) async throws -> String {
        let timeoutSeconds = configuration.backend == .integrated ? 600 : 30
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await performTranscription(
                    wav: wav,
                    configuration: configuration,
                    streamResults: streamResults,
                    onEvent: onEvent,
                    onUsage: onUsage
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                if configuration.backend == .integrated {
                    throw TranscriptionError.localTimedOut(seconds: timeoutSeconds)
                } else {
                    throw TranscriptionError.timedOut
                }
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw TranscriptionError.invalidResponse
            }
            return result
        }
    }

    private func performTranscription(
        wav: Data,
        configuration: TranscriptionConfiguration,
        streamResults: Bool,
        onEvent: StreamingASRPartialHandler?,
        onUsage: (@Sendable (TokenUsage) -> Void)?
    ) async throws -> String {
        if configuration.backend == .integrated {
            let text = try await NativeASRClient.shared.transcribe(wav: wav, configuration: configuration)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw TranscriptionError.emptyText }
            if streamResults {
                onEvent?(.partial(trimmed))
                onEvent?(.final(trimmed))
                onEvent?(.done)
            }
            return trimmed
        }

        guard let url = URL(string: configuration.endpoint) else {
            throw TranscriptionError.invalidEndpoint
        }
        guard EndpointSecurity.allowsCredentialTransmission(to: url, apiKey: configuration.apiKey) else {
            throw TranscriptionError.insecureEndpoint
        }

        let boundary = MultipartForm.randomBoundary(prefix: "VibeVoiceOSS")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if streamResults {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        if let authorization = EndpointSecurity.bearerHeader(apiKey: configuration.apiKey) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = multipartBody(
            boundary: boundary,
            wav: wav,
            configuration: configuration,
            stream: streamResults
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 8_192 { break }
            }
            throw TranscriptionError.server(
                status: http.statusCode,
                message: HTTPErrorBody.summarize(data)
            )
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if streamResults, contentType.contains("text/event-stream") {
            let text = try await consumeSSE(bytes: bytes, onEvent: onEvent, onUsage: onUsage)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw TranscriptionError.emptyText }
            onEvent?(.final(trimmed))
            onEvent?(.done)
            return trimmed
        }

        // A transcript JSON is kilobytes; anything past this is a misrouted response
        // (proxy page, model dump) that would otherwise be buffered in full.
        let responseByteLimit = 32 * 1024 * 1024
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= responseByteLimit else {
                throw TranscriptionError.invalidResponse
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawText = object["text"] as? String else {
            throw TranscriptionError.invalidResponse
        }
        if let usage = TokenUsage.parse(object["usage"]) { onUsage?(usage) }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyText }
        if streamResults {
            onEvent?(.partial(text))
            onEvent?(.final(text))
            onEvent?(.done)
        }
        return text
    }

    private func consumeSSE(
        bytes: URLSession.AsyncBytes,
        onEvent: StreamingASRPartialHandler?,
        onUsage: (@Sendable (TokenUsage) -> Void)?
    ) async throws -> String {
        var assembled = ""
        var eventType = "message"
        var dataLines: [String] = []

        func flush() {
            guard !dataLines.isEmpty else {
                eventType = "message"
                return
            }
            let payload = dataLines.joined(separator: "\n")
            dataLines = []
            let type = eventType
            eventType = "message"
            handleSSEPayload(
                type: type, payload: payload, assembled: &assembled,
                onEvent: onEvent, onUsage: onUsage
            )
        }

        for try await line in bytes.lines {
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
                eventType = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("data:") {
                dataLines.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                continue
            }
        }
        flush()

        return assembled
    }

    private func handleSSEPayload(
        type: String,
        payload: String,
        assembled: inout String,
        onEvent: StreamingASRPartialHandler?,
        onUsage: (@Sendable (TokenUsage) -> Void)?
    ) {
        if payload == "[DONE]" {
            onEvent?(.done)
            return
        }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Plain-text delta
            if !payload.isEmpty {
                assembled += payload
                onEvent?(.partial(assembled))
            }
            return
        }

        let eventName = (json["type"] as? String) ?? type
        if let usage = TokenUsage.parse(json["usage"]) { onUsage?(usage) }
        if eventName.contains("done") || eventName == "transcript.text.done" {
            if let text = json["text"] as? String, !text.isEmpty {
                assembled = text
            } else if let text = nestedText(json), !text.isEmpty {
                assembled = text
            }
            onEvent?(.final(assembled))
            return
        }

        let delta =
            (json["delta"] as? String)
            ?? (json["text"] as? String)
            ?? nestedText(json)
            ?? ""

        guard !delta.isEmpty else { return }

        // OpenAI-style deltas are incremental; some servers send cumulative `text`.
        if eventName.contains("delta") || json["delta"] != nil {
            assembled += delta
        } else if delta.hasPrefix(assembled) || assembled.isEmpty {
            assembled = delta
        } else {
            assembled += delta
        }
        onEvent?(.partial(assembled))
    }

    private func nestedText(_ json: [String: Any]) -> String? {
        if let text = json["text"] as? String { return text }
        if let transcript = json["transcript"] as? [String: Any],
           let text = transcript["text"] as? String {
            return text
        }
        return nil
    }

    func checkServer(configuration: TranscriptionConfiguration) async throws {
        if configuration.backend == .integrated {
            try await NativeASRClient.shared.checkRuntime(configuration: configuration)
            return
        }

        guard let transcriptionURL = URL(string: configuration.endpoint) else {
            throw TranscriptionError.invalidEndpoint
        }
        guard EndpointSecurity.allowsCredentialTransmission(
            to: transcriptionURL, apiKey: configuration.apiKey
        ) else {
            throw TranscriptionError.insecureEndpoint
        }
        let modelsURL = transcriptionURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 10
        if let authorization = EndpointSecurity.bearerHeader(apiKey: configuration.apiKey) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscriptionError.invalidResponse
        }
    }

    private func multipartBody(
        boundary: String,
        wav: Data,
        configuration: TranscriptionConfiguration,
        stream: Bool
    ) -> Data {
        var form = MultipartForm(boundary: boundary)
        form.addField("model", configuration.model)
        form.addField("language", configuration.language)
        form.addField("prompt", configuration.prompt)
        form.addField("response_format", "json")
        if stream {
            form.addField("stream", "true")
        }
        form.addFile("file", filename: "recording.wav", contentType: "audio/wav", data: wav)
        return form.finished()
    }
}

extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
