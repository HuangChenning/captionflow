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

    func testRefinementRequestIncludesSourceDraftAndApprovedGlossary() async throws {
        let responseJSON = Data(#"{"content":[{"type":"text","text":"会议纪要"}]}"#.utf8)
        let translator = LLMTranslator(configuration: configuration, apiKey: "test-key") { request in
            let body = String(decoding: request.httpBody!, as: UTF8.self)
            XCTAssertTrue(body.contains("meeting notes"))
            XCTAssertTrue(body.contains("会议记录"))
            XCTAssertTrue(body.contains("minutes=会议纪要"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (responseJSON, response)
        }

        let result = try await translator.refine(
            english: "meeting notes",
            localDraft: "会议记录",
            glossary: [GlossaryEntry(source: "minutes", target: "会议纪要")]
        )

        XCTAssertEqual(result, "会议纪要")
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
