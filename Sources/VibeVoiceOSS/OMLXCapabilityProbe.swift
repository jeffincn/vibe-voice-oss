import Foundation

/// Snapshot of what the local oMLX (or compatible) server actually supports for Streaming.
struct OMLXCapabilities: Equatable, Sendable {
    var serverReachable: Bool
    var openAPIVersion: String?
    var transcriptionEndpointOK: Bool
    /// Server returned `text/event-stream` when `stream=true` was requested.
    var supportsResultSSE: Bool
    /// A realtime / audio-ingress WebSocket-style path answered without 404.
    var supportsRealtimeIngress: Bool
    var detail: String

    static let unknown = OMLXCapabilities(
        serverReachable: false,
        openAPIVersion: nil,
        transcriptionEndpointOK: false,
        supportsResultSSE: false,
        supportsRealtimeIngress: false,
        detail: "尚未探测"
    )

    var summary: String {
        guard serverReachable else { return detail }
        if detail.hasPrefix("本地原生") { return detail }
        var parts: [String] = []
        if let openAPIVersion { parts.append("oMLX \(openAPIVersion)") }
        parts.append(supportsResultSSE ? "SSE 结果流：有" : "SSE 结果流：无")
        parts.append(supportsRealtimeIngress ? "音频入站 Realtime：有" : "音频入站 Realtime：无")
        return parts.joined(separator: " · ")
    }
}

enum OMLXCapabilityProbe {
    static func probe(configuration: TranscriptionConfiguration) async -> OMLXCapabilities {
        if configuration.backend == .integrated {
            return OMLXCapabilities(
                serverReachable: true,
                openAPIVersion: nil,
                transcriptionEndpointOK: true,
                supportsResultSSE: false,
                supportsRealtimeIngress: false,
                detail: "本地原生 ASR 集成模式：不使用 oMLX Streaming 探测"
            )
        }

        guard let transcriptionURL = URL(string: configuration.endpoint) else {
            return OMLXCapabilities(
                serverReachable: false,
                openAPIVersion: nil,
                transcriptionEndpointOK: false,
                supportsResultSSE: false,
                supportsRealtimeIngress: false,
                detail: "转写接口地址无效"
            )
        }

        let root = transcriptionURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let openAPIURL = root.appendingPathComponent("openapi.json")
        let modelsURL = transcriptionURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models")

        var openAPIVersion: String?
        var reachable = false

        if let (data, response) = try? await get(openAPIURL, apiKey: configuration.apiKey),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let info = json["info"] as? [String: Any] {
            reachable = true
            openAPIVersion = info["version"] as? String
        }

        if !reachable,
           let (_, response) = try? await get(modelsURL, apiKey: configuration.apiKey),
           let http = response as? HTTPURLResponse,
           (200..<500).contains(http.statusCode) {
            reachable = true
        }

        guard reachable else {
            return OMLXCapabilities(
                serverReachable: false,
                openAPIVersion: nil,
                transcriptionEndpointOK: false,
                supportsResultSSE: false,
                supportsRealtimeIngress: false,
                detail: "无法连接 oMLX"
            )
        }

        let silentWAV = minimalSilentWAV()
        let sse = await probeResultSSE(
            transcriptionURL: transcriptionURL,
            configuration: configuration,
            wav: silentWAV
        )

        let realtimeCandidates = [
            root.appendingPathComponent("v1/realtime"),
            root.appendingPathComponent("realtime"),
            root.appendingPathComponent("v1/audio/stream")
        ]
        var supportsRealtime = false
        for url in realtimeCandidates {
            if let (_, response) = try? await get(url, apiKey: configuration.apiKey),
               let http = response as? HTTPURLResponse,
               http.statusCode != 404 {
                // 405/401/426 still mean the route exists in some form.
                supportsRealtime = true
                break
            }
        }

        return OMLXCapabilities(
            serverReachable: true,
            openAPIVersion: openAPIVersion,
            transcriptionEndpointOK: sse.endpointOK,
            supportsResultSSE: sse.supportsSSE,
            supportsRealtimeIngress: supportsRealtime,
            detail: sse.note
        )
    }

    private struct SSEProbe {
        var endpointOK: Bool
        var supportsSSE: Bool
        var note: String
    }

    private static func probeResultSSE(
        transcriptionURL: URL,
        configuration: TranscriptionConfiguration,
        wav: Data
    ) async -> SSEProbe {
        let boundary = "VibeProbe-\(UUID().uuidString)"
        var request = URLRequest(url: transcriptionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = multipart(
            boundary: boundary,
            wav: wav,
            model: configuration.model,
            language: configuration.language,
            stream: true
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return SSEProbe(endpointOK: false, supportsSSE: false, note: "无效响应")
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let ok = (200..<300).contains(http.statusCode)
            if contentType.contains("text/event-stream") {
                return SSEProbe(endpointOK: ok, supportsSSE: true, note: "stream=true 返回 SSE")
            }
            if ok {
                return SSEProbe(
                    endpointOK: true,
                    supportsSSE: false,
                    note: "stream=true 仍返回 JSON（本机无结果 SSE）"
                )
            }
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            return SSEProbe(endpointOK: false, supportsSSE: false, note: message)
        } catch {
            return SSEProbe(endpointOK: false, supportsSSE: false, note: error.localizedDescription)
        }
    }

    private static func get(_ url: URL, apiKey: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return try await URLSession.shared.data(for: request)
    }

    private static func multipart(
        boundary: String,
        wav: Data,
        model: String,
        language: String,
        stream: Bool
    ) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", model)
        if !language.isEmpty { field("language", language) }
        field("response_format", "json")
        if stream { field("stream", "true") }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"probe.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// 100 ms of silence @ 16 kHz mono PCM16.
    private static func minimalSilentWAV() -> Data {
        WAVEncoder.encode(samples: [Float](repeating: 0, count: 1_600), inputSampleRate: 16_000)
    }
}
