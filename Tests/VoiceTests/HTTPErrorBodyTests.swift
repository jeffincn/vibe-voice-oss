import XCTest
@testable import VibeVoiceOSS

final class HTTPErrorBodyTests: XCTestCase {
    func testRedactsBearerTokensEchoedBackByTheProvider() {
        let body = #"{"error":"invalid request","headers":{"Authorization":"Bearer sk-abc123DEF456ghi"}}"#
        let summary = HTTPErrorBody.summarize(body)

        XCTAssertFalse(summary.contains("sk-abc123DEF456ghi"))
        XCTAssertTrue(summary.contains("Bearer ***"))
    }

    func testRedactsBareAPIKeys() {
        let summary = HTTPErrorBody.summarize("Incorrect API key provided: sk-proj-9aZ12345xyz")

        XCTAssertFalse(summary.contains("sk-proj-9aZ12345xyz"))
        XCTAssertTrue(summary.contains("sk-***"))
    }

    func testRedactsKeyValueSecretsInJSONAndFormBodies() {
        let json = HTTPErrorBody.summarize(#"{"api_key": "9f8e7d6c5b4a3", "model": "qwen"}"#)
        XCTAssertFalse(json.contains("9f8e7d6c5b4a3"))
        XCTAssertTrue(json.contains("qwen"), "non-secret fields must stay readable")

        let form = HTTPErrorBody.summarize("rejected: access_token=abcdef123456&model=qwen")
        XCTAssertFalse(form.contains("abcdef123456"))
        XCTAssertTrue(form.contains("model=qwen"))
    }

    func testTruncatesRunawayBodies() {
        let summary = HTTPErrorBody.summarize(Data(String(repeating: "A", count: 5_000_000).utf8))

        XCTAssertLessThanOrEqual(summary.count, HTTPErrorBody.characterLimit + 1)
        XCTAssertTrue(summary.hasSuffix("…"))
    }

    func testCollapsesWhitespaceSoHTMLErrorPagesStayOneLine() {
        let summary = HTTPErrorBody.summarize("<html>\n  <body>\n   Gateway Timeout\n  </body>\n</html>")

        XCTAssertEqual(summary, "<html> <body> Gateway Timeout </body> </html>")
    }

    func testShortCleanBodiesArePassedThroughUnchanged() {
        XCTAssertEqual(HTTPErrorBody.summarize("model not found"), "model not found")
    }

    func testEmptyAndInvalidBodiesFallBack() {
        XCTAssertEqual(HTTPErrorBody.summarize(Data()), "未知错误")
        XCTAssertEqual(HTTPErrorBody.summarize("   \n  "), "未知错误")
        XCTAssertEqual(HTTPErrorBody.summarize(Data(), fallback: "boom"), "boom")
        XCTAssertTrue(HTTPErrorBody.summarize(Data([0xFF, 0xFE, 0x41, 0x42])).contains("AB"))
    }
}
