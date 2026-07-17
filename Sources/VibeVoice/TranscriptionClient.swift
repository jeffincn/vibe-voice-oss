import Foundation

struct TranscriptionConfiguration: Sendable {
    let endpoint: String
    let model: String
    let language: String
    let prompt: String
    let apiKey: String
}

enum TranscriptionError: LocalizedError {
    case invalidEndpoint
    case server(status: Int, message: String)
    case invalidResponse
    case emptyText
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "oMLX 接口地址无效。"
        case let .server(status, message): "oMLX 返回 HTTP \(status)：\(message)"
        case .invalidResponse: "oMLX 返回了无法解析的响应。"
        case .emptyText: "识别完成，但返回文本为空。"
        case .timedOut: "转写超过 30 秒，已自动中断。"
        }
    }
}

struct TranscriptionClient: Sendable {
    private struct Response: Decodable { let text: String }

    func transcribe(wav: Data, configuration: TranscriptionConfiguration) async throws -> String {
        try await transcribe(
            wav: wav,
            configuration: configuration,
            streamResults: false,
            onEvent: nil
        )
    }

    /// Transcribe a complete WAV. When `streamResults` is true, requests `stream=true` and
    /// emits partial deltas if the server replies with SSE; otherwise falls back to JSON.
    func transcribe(
        wav: Data,
        configuration: TranscriptionConfiguration,
        streamResults: Bool,
        onEvent: StreamingASRPartialHandler?
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await performTranscription(
                    wav: wav,
                    configuration: configuration,
                    streamResults: streamResults,
                    onEvent: onEvent
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw TranscriptionError.timedOut
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
        onEvent: StreamingASRPartialHandler?
    ) async throws -> String {
        guard let url = URL(string: configuration.endpoint) else {
            throw TranscriptionError.invalidEndpoint
        }

        let boundary = "VibeVoice-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if streamResults {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        if !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
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
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw TranscriptionError.server(status: http.statusCode, message: message)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if streamResults, contentType.contains("text/event-stream") {
            let text = try await consumeSSE(bytes: bytes, onEvent: onEvent)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw TranscriptionError.emptyText }
            onEvent?(.final(trimmed))
            onEvent?(.done)
            return trimmed
        }

        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TranscriptionError.invalidResponse
        }
        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        onEvent: StreamingASRPartialHandler?
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
            handleSSEPayload(type: type, payload: payload, assembled: &assembled, onEvent: onEvent)
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
        onEvent: StreamingASRPartialHandler?
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
        guard let transcriptionURL = URL(string: configuration.endpoint) else {
            throw TranscriptionError.invalidEndpoint
        }
        let modelsURL = transcriptionURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 10
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
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
        var body = Data()
        func addField(_ name: String, _ value: String) {
            guard !value.isEmpty else { return }
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }

        addField("model", configuration.model)
        addField("language", configuration.language)
        addField("prompt", configuration.prompt)
        addField("response_format", "json")
        if stream {
            addField("stream", "true")
        }
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n")
        body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(string.data(using: .utf8)!)
    }
}
