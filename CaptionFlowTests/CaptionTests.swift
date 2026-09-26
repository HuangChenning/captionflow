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

    /// 字幕窗最多显示最近 5 条；UserDefaults 里的值可能超出范围（例如手动修改），显示时要限制住。
    func testVisibleCaptionCountIsClampedToOneThroughFive() {
        XCTAssertEqual(CaptionOverlaySettings.clampedVisibleCaptionCount(0), 1)
        XCTAssertEqual(CaptionOverlaySettings.clampedVisibleCaptionCount(3), 3)
        XCTAssertEqual(CaptionOverlaySettings.clampedVisibleCaptionCount(9), 5)
    }

    /// 黑字放在默认的深色背景上看不清，只有黑字改用浅色背景，其余颜色保持深色背景。
    func testOnlyBlackTextUsesLightBackground() {
        XCTAssertEqual(CaptionTextColor.allCases.filter(\.usesLightBackground), [.black])
    }
}
