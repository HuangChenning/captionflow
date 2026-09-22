import XCTest
@testable import CaptionFlow

final class EnglishASRTests: XCTestCase {
    func testNormalizeEnglishTranscriptTrimsWhitespace() {
        XCTAssertEqual(
            normalizeEnglishTranscript("  hello world  "),
            "hello world"
        )
    }

    func testIsNonSpeechTranscriptDetectsMusicTags() {
        XCTAssertTrue(isNonSpeechTranscript("[Music]"))
        XCTAssertTrue(isNonSpeechTranscript("(music playing)"))
        XCTAssertTrue(isNonSpeechTranscript("♪ ♪"))
    }

    func testIsNonSpeechTranscriptAllowsRealSpeech() {
        XCTAssertFalse(isNonSpeechTranscript("hello world"))
        XCTAssertFalse(isNonSpeechTranscript(""))
    }
}
