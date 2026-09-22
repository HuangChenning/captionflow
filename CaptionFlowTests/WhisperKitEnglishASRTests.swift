import XCTest
@testable import CaptionFlow

final class WhisperKitEnglishASRTests: XCTestCase {
    func testTranscribeNormalizesTranscriberOutput() async throws {
        let asr = WhisperKitEnglishASR { samples in
            XCTAssertEqual(samples, [0.1, 0.2])
            return "  hello world  \n"
        }

        let result = try await asr.transcribe(samples: [0.1, 0.2])

        XCTAssertEqual(result, "hello world")
    }

    func testTranscribePropagatesTranscriberError() async throws {
        struct StubError: Error {}
        let asr = WhisperKitEnglishASR { _ in throw StubError() }

        do {
            _ = try await asr.transcribe(samples: [0.0])
            XCTFail("expected StubError")
        } catch is StubError {
            // expected
        }
    }
}
