import XCTest
@testable import VibeVoiceOSS

final class ModelDownloadFailureTests: XCTestCase {
    /// Stands in for the untyped errors Hub and WhisperKit throw, where the message is
    /// the only thing to go on.
    private struct HubError: Error, CustomStringConvertible {
        let description: String
    }

    func testTimeoutsAreWorthRetrying() {
        XCTAssertEqual(ModelDownloadFailure.classify(URLError(.timedOut)), .transient)
        XCTAssertEqual(ModelDownloadFailure.classify(URLError(.networkConnectionLost)), .transient)
        XCTAssertEqual(ModelDownloadFailure.classify(URLError(.notConnectedToInternet)), .transient)
    }

    func testCancellationIsNotAFailure() {
        XCTAssertEqual(ModelDownloadFailure.classify(CancellationError()), .cancelled)
        XCTAssertEqual(ModelDownloadFailure.classify(URLError(.cancelled)), .cancelled)
    }

    func testCredentialFailuresAreNotRetried() {
        XCTAssertEqual(
            ModelDownloadFailure.classify(URLError(.userAuthenticationRequired)),
            .permanent(.authenticationRequired)
        )
        XCTAssertEqual(
            ModelDownloadFailure.classify(HubError(description: "HTTP 403 gated repo")),
            .permanent(.authenticationRequired)
        )
    }

    /// The reason the string matching was replaced: localizedDescription is translated,
    /// so the English keywords never appeared on a non-English system.
    func testUntranslatedEnumCaseNameIsEnoughToClassify() {
        enum HubClientError: Error { case unauthorized(String) }
        XCTAssertEqual(
            ModelDownloadFailure.classify(HubClientError.unauthorized("需要登录")),
            .permanent(.authenticationRequired)
        )
    }

    func testStatusCodeIsNotMatchedInsideALargerNumber() {
        // "1401" and "4038" used to read as 401 and 403.
        XCTAssertEqual(
            ModelDownloadFailure.classify(HubError(description: "stalled after 1401 of 4038 bytes")),
            .transient
        )
    }

    func testMissingRepositoryIsNotRetried() {
        XCTAssertEqual(
            ModelDownloadFailure.classify(HubError(description: "HTTP 404: repository not found")),
            .permanent(.repositoryNotFound)
        )
    }

    func testFullDiskIsNotRetried() {
        XCTAssertEqual(
            ModelDownloadFailure.classify(CocoaError(.fileWriteOutOfSpace)),
            .permanent(.outOfSpace)
        )
        XCTAssertEqual(ModelDownloadFailure.classify(POSIXError(.ENOSPC)), .permanent(.outOfSpace))
    }

    func testUnderlyingErrorIsInspected() {
        let wrapped = NSError(
            domain: "HubApi",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: URLError(.userAuthenticationRequired) as NSError]
        )
        XCTAssertEqual(ModelDownloadFailure.classify(wrapped), .permanent(.authenticationRequired))
    }

    func testEveryPermanentReasonTellsTheUserWhatToDo() {
        let reasons: [ModelDownloadFailure.Reason] = [
            .authenticationRequired, .repositoryNotFound, .outOfSpace, .cannotWrite, .invalidEndpoint
        ]
        for reason in reasons {
            let failure = ModelDownloadFailure.permanent(reason)
            XCTAssertFalse(failure.isRetryable)
            XCTAssertFalse(failure.advice?.isEmpty ?? true, "no advice for \(reason)")
        }
        XCTAssertNil(ModelDownloadFailure.transient.advice)
        XCTAssertTrue(ModelDownloadFailure.transient.isRetryable)
    }
}
