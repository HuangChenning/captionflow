import XCTest
@testable import CaptionFlow

final class CaptionTests: XCTestCase {
    func testReplacingProvisionalCaptionKeepsItsIdentity() {
        let id = UUID()
        let caption = Caption(
            id: id,
            english: "hello",
            chinese: "你好",
            isProvisional: true,
            createdAt: .now
        )

        XCTAssertEqual(
            caption.replacing(english: "hello world", chinese: "你好，世界").id,
            id
        )
    }
}
