import XCTest
@testable import VibeVoiceOSS

final class EndpointSecurityTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string), "invalid test URL: \(string)")
    }

    // MARK: - Credential transmission

    func testTLSSchemesAlwaysAllowCredentials() throws {
        XCTAssertTrue(EndpointSecurity.allowsCredentialTransmission(
            to: try url("https://api.example.com/v1/chat/completions"), apiKey: "sk-secret"
        ))
        XCTAssertTrue(EndpointSecurity.allowsCredentialTransmission(
            to: try url("wss://api.example.com/v1/audio/stream"), apiKey: "sk-secret"
        ))
    }

    func testCleartextRemoteRejectsCredentials() throws {
        XCTAssertFalse(EndpointSecurity.allowsCredentialTransmission(
            to: try url("http://api.example.com/v1/chat/completions"), apiKey: "sk-secret"
        ))
        XCTAssertFalse(EndpointSecurity.allowsCredentialTransmission(
            to: try url("ws://api.example.com/v1/audio/stream"), apiKey: "sk-secret"
        ))
    }

    func testLoopbackAllowsCredentialsOverCleartext() throws {
        let hosts = [
            "http://127.0.0.1:8000/v1/chat/completions",
            "http://127.0.0.53:8000/v1/chat/completions",
            "http://localhost:8000/v1/chat/completions",
            "http://api.localhost:8000/v1/chat/completions",
            "http://[::1]:8000/v1/chat/completions",
            "ws://127.0.0.1:8000/v1/audio/stream",
        ]
        for host in hosts {
            XCTAssertTrue(
                EndpointSecurity.allowsCredentialTransmission(to: try url(host), apiKey: "sk-secret"),
                "expected loopback to be allowed: \(host)"
            )
        }
    }

    func testAmbiguousLoopbackNotationsFailClosed() throws {
        // Shorthand / decimal forms are not parsed as loopback; they must not carry a key.
        let hosts = [
            "http://127.1:8000/v1/chat/completions",
            "http://2130706433:8000/v1/chat/completions",
            "http://127.0.0.1.example.com/v1/chat/completions",
        ]
        for host in hosts {
            XCTAssertFalse(
                EndpointSecurity.allowsCredentialTransmission(to: try url(host), apiKey: "sk-secret"),
                "expected ambiguous host to fail closed: \(host)"
            )
        }
    }

    func testUnknownSchemeRejectsCredentials() throws {
        XCTAssertFalse(EndpointSecurity.allowsCredentialTransmission(
            to: try url("ftp://api.example.com/v1"), apiKey: "sk-secret"
        ))
        XCTAssertFalse(EndpointSecurity.allowsCredentialTransmission(
            to: try url("file:///tmp/model"), apiKey: "sk-secret"
        ))
    }

    func testEmptyKeySkipsCredentialGuard() throws {
        XCTAssertTrue(EndpointSecurity.allowsCredentialTransmission(
            to: try url("http://api.example.com/v1/chat/completions"), apiKey: ""
        ))
        XCTAssertTrue(EndpointSecurity.allowsCredentialTransmission(
            to: try url("http://api.example.com/v1/chat/completions"), apiKey: "   \n"
        ))
    }

    // MARK: - Clear-text payload exposure

    func testCleartextRemoteDetectedWithoutAPIKey() {
        XCTAssertTrue(EndpointSecurity.isCleartextRemote(
            endpoint: "http://api.example.com/v1/audio/transcriptions"
        ))
        XCTAssertTrue(EndpointSecurity.isCleartextRemote(
            endpoint: "ws://api.example.com/v1/audio/stream"
        ))
    }

    func testCleartextRemoteIgnoresLoopbackAndTLS() {
        let safe = [
            "http://127.0.0.1:8000/v1/audio/transcriptions",
            "http://localhost:8000/v1/audio/transcriptions",
            "https://api.example.com/v1/audio/transcriptions",
            "wss://api.example.com/v1/audio/stream",
        ]
        for endpoint in safe {
            XCTAssertFalse(
                EndpointSecurity.isCleartextRemote(endpoint: endpoint),
                "expected no clear-text warning: \(endpoint)"
            )
        }
    }

    func testCleartextRemoteIgnoresBlankAndInvalidEndpoints() {
        XCTAssertFalse(EndpointSecurity.isCleartextRemote(endpoint: ""))
        XCTAssertFalse(EndpointSecurity.isCleartextRemote(endpoint: "   "))
    }
}
