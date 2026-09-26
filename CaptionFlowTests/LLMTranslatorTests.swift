import XCTest
@testable import CaptionFlow

final class LLMTranslatorTests: XCTestCase {
    private let configuration = LLMConfiguration(
        baseURL: URL(string: "https://api.minimaxi.com/anthropic")!,
        model: "MiniMax-M3",
        instruction: "Translate English speech into concise, natural Simplified Chinese subtitles."
    )!

    func testTranslateParsesAnthropicMessagesResponse() async throws {
        let responseJSON = Data("""
        {"content":[{"type":"text","text":"你好，你好吗？"}]}
        """.utf8)

        let translator = LLMTranslator(configuration: configuration, apiKey: "test-key") { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.minimaxi.com/anthropic/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (responseJSON, response)
        }

        let result = try await translator.translate("Hello, how are you?")

        XCTAssertEqual(result, "你好，你好吗？")
    }

    /// 用户确认的术语必须进入精修请求，否则词库对字幕没有任何作用。
    func testRefinementRequestIncludesSourceDraftAndApprovedGlossary() async throws {
        let body = try await capturedRequestBody(glossary: [GlossaryEntry(source: "minutes", target: "会议纪要")]) {
            try await $0.refine(english: "Please send the Minutes", localDraft: "请发送分钟")
        }

        XCTAssertTrue(body.contains("Please send the Minutes"))
        XCTAssertTrue(body.contains("请发送分钟"), "the LLM must see the local draft so it can correct it")
        XCTAssertTrue(body.contains("minutes=会议纪要"), "matching is case-insensitive")
    }

    /// 只附带原文里出现的术语：其余词条对这一句没有用，还会增加请求长度。
    func testRefinementOmitsGlossaryTermsNotInSource() async throws {
        let body = try await capturedRequestBody(glossary: [GlossaryEntry(source: "minutes", target: "会议纪要")]) {
            try await $0.refine(english: "hello", localDraft: nil)
        }

        XCTAssertFalse(body.contains("会议纪要"))
        XCTAssertFalse(body.contains("glossary"))
    }

    /// 仅 LLM 模式下没有精修步骤，术语要在直接翻译时生效。
    func testTranslateAlsoAppliesGlossary() async throws {
        let body = try await capturedRequestBody(glossary: [GlossaryEntry(source: "minutes", target: "会议纪要")]) {
            try await $0.translate("the minutes")
        }

        XCTAssertTrue(body.contains("minutes=会议纪要"))
    }

    private func capturedRequestBody(
        glossary: [GlossaryEntry],
        _ call: (LLMTranslator) async throws -> String
    ) async throws -> String {
        let captured = BodyBox()
        let responseJSON = Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8)
        let translator = LLMTranslator(configuration: configuration, apiKey: "test-key", glossary: glossary) { request in
            captured.value = String(decoding: request.httpBody!, as: UTF8.self)
            return (responseJSON, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await call(translator)
        return try XCTUnwrap(captured.value)
    }

    func testTranslateParsesOpenAIChatCompletionsResponse() async throws {
        let openAIConfiguration = LLMConfiguration(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            model: "gpt-4.1-mini",
            instruction: "Translate English speech into concise, natural Simplified Chinese subtitles."
        )!
        let responseJSON = Data("""
        {"choices":[{"message":{"role":"assistant","content":"你好，你好吗？"}}]}
        """.utf8)

        let translator = LLMTranslator(configuration: openAIConfiguration, apiKey: "test-key", style: .openAICompatible) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (responseJSON, response)
        }

        let result = try await translator.translate("Hello, how are you?")

        XCTAssertEqual(result, "你好，你好吗？")
    }

    func testTranslateThrowsOnNonSuccessStatus() async throws {
        let translator = LLMTranslator(configuration: configuration, apiKey: "test-key") { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        do {
            _ = try await translator.translate("Hello")
            XCTFail("expected LLMTranslatorError.httpStatus")
        } catch LLMTranslatorError.httpStatus(let status) {
            XCTAssertEqual(status, 401)
        }
    }

    func testTranslateRejectsEmptyAPIKeyBeforeSendingAnyRequest() async throws {
        let translator = LLMTranslator(configuration: configuration, apiKey: "") { _ in
            XCTFail("must not perform a network request without an API key")
            return (Data(), URLResponse())
        }

        do {
            _ = try await translator.translate("Hello")
            XCTFail("expected LLMTranslatorError.emptyAPIKey")
        } catch LLMTranslatorError.emptyAPIKey {
            // expected
        }
    }
}

private final class BodyBox: @unchecked Sendable {
    var value: String?
}
