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

    /// 字幕历史里保存的旧记录没有 refinement 字段，升级后仍要能读取。
    func testDecodesCaptionSavedBeforeRefinementExisted() throws {
        let json = """
        {"id":"\(UUID().uuidString)","english":"hello","chinese":"你好","isProvisional":false,"createdAt":0}
        """
        let caption = try JSONDecoder().decode(Caption.self, from: Data(json.utf8))

        XCTAssertEqual(caption.chinese, "你好")
        XCTAssertNil(caption.refinement)
    }
}
