import XCTest
@testable import VibeVoiceOSS

final class MultipartFormTests: XCTestCase {
    private func text(_ form: MultipartForm) -> String {
        String(decoding: form.finished(), as: UTF8.self)
    }

    func testFieldsAndFileAreDelimitedAndTerminated() {
        var form = MultipartForm(boundary: "B")
        form.addField("model", "whisper-1")
        form.addFile("file", filename: "recording.wav", contentType: "audio/wav", data: Data([1, 2]))

        XCTAssertEqual(text(form), """
        --B\r
        Content-Disposition: form-data; name="model"\r
        \r
        whisper-1\r
        --B\r
        Content-Disposition: form-data; name="file"; filename="recording.wav"\r
        Content-Type: audio/wav\r
        \r
        \u{1}\u{2}\r
        --B--\r\n
        """)
    }

    func testEmptyFieldsAreOmitted() {
        var form = MultipartForm(boundary: "B")
        form.addField("language", "")
        XCTAssertEqual(text(form), "--B--\r\n")
    }

    func testQuotesAndNewlinesInAFilenameCannotBreakTheHeader() {
        var form = MultipartForm(boundary: "B")
        form.addFile(
            "file",
            filename: "a\".wav\r\nX-Injected: 1",
            contentType: "audio/wav",
            data: Data()
        )
        let body = text(form)
        XCTAssertTrue(body.contains(#"filename="a%22.wav%0D%0AX-Injected: 1""#))
        XCTAssertFalse(body.contains("\r\nX-Injected"), "the header block must not gain a line")
    }

    func testFieldValuesKeepTheirNewlinesVerbatim() {
        // A multi-line prompt is legitimate: the part body runs until the next delimiter.
        var form = MultipartForm(boundary: "B")
        form.addField("prompt", "line one\nline two")
        XCTAssertTrue(text(form).contains("\r\n\r\nline one\nline two\r\n--B--"))
    }

    func testRandomBoundaryIsUniquePerBody() {
        let first = MultipartForm.randomBoundary(prefix: "VibeVoiceOSS")
        let second = MultipartForm.randomBoundary(prefix: "VibeVoiceOSS")
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasPrefix("VibeVoiceOSS-"))
    }
}
