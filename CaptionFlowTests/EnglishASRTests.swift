import XCTest
@testable import CaptionFlow

final class EnglishASRTests: XCTestCase {
    func testNormalizeEnglishTranscriptTrimsWhitespace() {
        XCTAssertEqual(
            normalizeEnglishTranscript("  hello world  "),
            "hello world"
        )
    }
}
