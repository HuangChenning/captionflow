import XCTest
@testable import CaptionFlow

private struct StubTranslator: Translator {
    let delay: Duration
    let result: String

    func translate(_ text: String) async throws -> String {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return result
    }
}

final class FallbackTranslatorTests: XCTestCase {
    func testFastPrimaryNeverTriggersFallback() async throws {
        let primary = StubTranslator(delay: .zero, result: "fast LLM result")
        let fallback = StubTranslator(delay: .zero, result: "local fallback result")
        var provisionalCalls: [String] = []

        let translator = FallbackTranslator(
            primary: primary,
            fallback: fallback,
            timeout: .seconds(1),
            onProvisional: { provisionalCalls.append($0) }
        )

        let result = try await translator.translate("hello")

        XCTAssertEqual(result, "fast LLM result")
        XCTAssertTrue(provisionalCalls.isEmpty, "fallback must stay unused when the LLM answers before the timeout")
    }

    func testSlowPrimaryIsProvisionallyCoveredByFallbackThenRevisedByPrimary() async throws {
        let primary = StubTranslator(delay: .milliseconds(200), result: "final LLM result")
        let fallback = StubTranslator(delay: .zero, result: "local fallback result")
        var provisionalCalls: [String] = []

        let translator = FallbackTranslator(
            primary: primary,
            fallback: fallback,
            timeout: .milliseconds(20),
            onProvisional: { provisionalCalls.append($0) }
        )

        let result = try await translator.translate("hello")

        XCTAssertEqual(provisionalCalls, ["local fallback result"], "a slow LLM must surface the local translation as a provisional line")
        XCTAssertEqual(result, "final LLM result", "the LLM result must still win as the final, revised translation")
    }
}
