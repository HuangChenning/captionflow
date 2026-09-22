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
