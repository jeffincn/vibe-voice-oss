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

    /// A box on the same LAN is not loopback: the key crosses a wire someone else
    /// can be on, which is the case a self-hosted setup most easily gets wrong.
    func testPrivateNetworkHostsRejectCredentialsOverCleartext() throws {
        let hosts = [
            "http://192.168.1.20:8000/v1/chat/completions",
            "http://10.0.0.5:8000/v1/chat/completions",
            "http://mac-studio.local:8000/v1/chat/completions",
        ]
        for host in hosts {
            XCTAssertFalse(
                EndpointSecurity.allowsCredentialTransmission(to: try url(host), apiKey: "sk-secret"),
                "expected LAN host to be refused: \(host)"
            )
            XCTAssertTrue(
                EndpointSecurity.allowsCredentialTransmission(to: try url(host), apiKey: ""),
                "with no key there is nothing to protect: \(host)"
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

    // MARK: - Authorization header

    func testBearerHeaderTrimsPastedWhitespace() {
        // A paste from a file or password manager routinely carries a trailing newline.
        XCTAssertEqual(EndpointSecurity.bearerHeader(apiKey: "sk-secret\n"), "Bearer sk-secret")
        XCTAssertEqual(EndpointSecurity.bearerHeader(apiKey: "  sk-secret  "), "Bearer sk-secret")
    }

    func testBearerHeaderIsNilWithoutAKey() {
        XCTAssertNil(EndpointSecurity.bearerHeader(apiKey: ""))
        XCTAssertNil(EndpointSecurity.bearerHeader(apiKey: " \n\t"))
    }

    func testBearerHeaderRejectsInteriorControlCharacters() {
        // Trimming cannot fix these, and sending them would smuggle the remainder into
        // the header block.
        XCTAssertNil(EndpointSecurity.bearerHeader(apiKey: "sk-one\r\nX-Admin: true"))
        XCTAssertNil(EndpointSecurity.bearerHeader(apiKey: "sk\u{0}two"))
    }
}
