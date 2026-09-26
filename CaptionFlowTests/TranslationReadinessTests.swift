import Translation
import XCTest
@testable import CaptionFlow

final class TranslationRouteTests: XCTestCase {
    /// 本地资源未安装时不能走本地翻译，否则字幕会卡在系统下载提示上。
    func testAutoSkipsLocalTranslationWhenResourcesAreMissing() {
        XCTAssertEqual(TranslationEngineMode.auto.route(localReady: false, llmAvailable: true), .llmOnly)
        XCTAssertEqual(TranslationEngineMode.auto.route(localReady: false, llmAvailable: false), .englishOnly)
    }

    func testAutoUsesLocalDraftWhenResourcesAreInstalled() {
        XCTAssertEqual(TranslationEngineMode.auto.route(localReady: true, llmAvailable: true), .localThenLLM)
        XCTAssertEqual(TranslationEngineMode.auto.route(localReady: true, llmAvailable: false), .localOnly)
    }

    /// 仅本地模式不能偷偷改用 LLM：用户可能不希望字幕内容发到外部服务。
    func testLocalOnlyNeverFallsBackToLLM() {
        XCTAssertEqual(TranslationEngineMode.localOnly.route(localReady: false, llmAvailable: true), .englishOnly)
        XCTAssertEqual(TranslationEngineMode.localOnly.route(localReady: true, llmAvailable: true), .localOnly)
    }

    func testLLMOnlyFallsBackToLocalOnlyWhenNoLLMIsConfigured() {
        XCTAssertEqual(TranslationEngineMode.llmOnly.route(localReady: true, llmAvailable: false), .localOnly)
        XCTAssertEqual(TranslationEngineMode.llmOnly.route(localReady: false, llmAvailable: false), .englishOnly)
    }
}

@MainActor
final class TranslationNoticeTests: XCTestCase {
    /// 资源缺失时用户要知道为什么没有本地译文，以及去哪里下载。
    func testMissingResourcesExplainFallbackAndWhereToDownload() throws {
        let notice = try XCTUnwrap(CaptionSessionController.notice(
            for: .englishOnly, mode: .auto, readiness: .downloadable, target: .japanese
        ))
        XCTAssertTrue(notice.contains("日语"))
        XCTAssertTrue(notice.contains("只显示英文"))
        XCTAssertTrue(notice.contains("翻译设置"))
    }

    func testNoNoticeWhenUserChoseLLMOnly() {
        XCTAssertNil(CaptionSessionController.notice(for: .llmOnly, mode: .llmOnly, readiness: .downloadable, target: .japanese))
    }

    func testNoNoticeWhenLocalTranslationIsUsed() {
        XCTAssertNil(CaptionSessionController.notice(for: .localThenLLM, mode: .auto, readiness: .installed, target: .simplifiedChinese))
    }
}

@MainActor
final class LocalTranslationReadinessTests: XCTestCase {
    func testChecksTheSelectedTargetLanguage() async {
        let checked = LanguageBox()
        let readiness = LocalTranslationReadiness { source, target in
            checked.value = (source.minimalIdentifier, target.minimalIdentifier)
            return .installed
        }

        await readiness.refresh(target: .japanese)

        XCTAssertEqual(checked.value?.0, "en")
        XCTAssertEqual(checked.value?.1, "ja")
        XCTAssertTrue(readiness.isReady)
    }

    func testMapsAvailabilityStatus() async {
        for (status, expected) in [
            (LanguageAvailability.Status.supported, LocalTranslationReadiness.State.downloadable),
            (.unsupported, .unsupported),
        ] {
            let readiness = LocalTranslationReadiness { _, _ in status }
            await readiness.refresh(target: .simplifiedChinese)
            XCTAssertEqual(readiness.state, expected)
            XCTAssertFalse(readiness.isReady)
        }
    }

    /// 下载成功后要重新检查，不能假定已安装（例如用户在系统提示里取消了下载）。
    func testPrepareRechecksInsteadOfAssumingInstalled() async {
        let readiness = LocalTranslationReadiness { _, _ in .supported }
        await readiness.refresh(target: .simplifiedChinese)

        await readiness.prepare {}

        XCTAssertEqual(readiness.state, .downloadable)
    }

    func testPrepareFailureIsReported() async {
        struct DownloadError: LocalizedError { var errorDescription: String? { "网络不可用" } }
        let readiness = LocalTranslationReadiness { _, _ in .supported }

        await readiness.prepare { throw DownloadError() }

        XCTAssertEqual(readiness.state, .failed("网络不可用"))
        XCTAssertFalse(readiness.isReady)
    }
}

private final class LanguageBox: @unchecked Sendable {
    var value: (String, String)?
}
