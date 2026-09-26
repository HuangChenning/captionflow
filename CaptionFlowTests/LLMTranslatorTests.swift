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

    /// 默认开启思考的模型会把 max_tokens 用在思考上、不返回译文（2026-09-26 验收中 10 句失败 5 句），所以请求要关闭思考。
    func testAnthropicRequestDisablesThinking() async throws {
        let body = try await capturedRequestBody(glossary: []) {
            try await $0.refine(english: "hello", localDraft: nil)
        }

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual((json["thinking"] as? [String: String])?["type"], "disabled")
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

    /// 模型常在 JSON 前后加说明文字；只要能找到术语数组就应当解析出来，而不是整次提取失败。
    func testProposeTermsParsesArrayWrappedInProse() async throws {
        let translator = translator(replying: #"Here are the terms: [{"source": "Kubernetes", "target": "Kubernetes"}, {"source": "minutes", "target": "会议纪要"}] Hope this helps."#)

        let terms = try await translator.proposeTerms(for: [caption("We deployed it on Kubernetes", "我们部署到了 Kubernetes")])

        XCTAssertEqual(terms.map(\.source), ["Kubernetes", "minutes"])
        XCTAssertEqual(terms.map(\.target), ["Kubernetes", "会议纪要"])
    }

    /// 回复无法解析时必须报错，否则用户会误以为这场会话里没有术语。
    func testProposeTermsThrowsWhenReplyIsNotATermList() async throws {
        let translator = translator(replying: "I could not find any terms.")

        do {
            _ = try await translator.proposeTerms(for: [caption("hello", "你好")])
            XCTFail("expected LLMTranslatorError.malformedTermList")
        } catch LLMTranslatorError.malformedTermList {
            // expected
        }
    }

    /// LLM 要看到原文和已有译文，才能判断哪些术语需要统一译法。
    func testProposeTermsSendsTranscriptWithTranslations() async throws {
        let body = try await capturedRequestBody(glossary: []) {
            // 模拟回复不是术语列表，这里只检查发出的请求内容。
            _ = try? await $0.proposeTerms(for: [caption("the minutes", "分钟"), Caption(id: UUID(), english: "no translation", chinese: nil, isProvisional: false, createdAt: .now)])
            return ""
        }

        XCTAssertTrue(body.contains("EN: the minutes\\nTranslation: 分钟"))
        XCTAssertTrue(body.contains("EN: no translation"))
    }

    /// 长会话要分段发送，每段不超过上限，且每句都被发送一次，不会被截掉。
    func testProposeTermsSplitsLongTranscriptIntoChunks() async throws {
        let bodies = BodiesBox()
        let responseJSON = Data(#"{"content":[{"type":"text","text":"[]"}]}"#.utf8)
        let translator = LLMTranslator(configuration: configuration, apiKey: "test-key") { request in
            bodies.values.append(String(decoding: request.httpBody!, as: UTF8.self))
            return (responseJSON, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let captions = (1...5).map { caption("sentence number \($0)", "第 \($0) 句") }

        // 每行约 40 字符，上限 100 时每段放两行。
        _ = try await translator.proposeTerms(for: captions, maxChunkCharacters: 100)

        XCTAssertEqual(bodies.values.count, 3)
        for number in 1...5 {
            XCTAssertEqual(bodies.values.filter { $0.contains("sentence number \(number)\\n") }.count, 1)
        }
    }

    /// 各段的术语都要返回，不能只保留最后一段。
    func testProposeTermsMergesTermsFromAllChunks() async throws {
        let replies = ["[{\"source\": \"Kubernetes\", \"target\": \"Kubernetes\"}]", "[{\"source\": \"sprint\", \"target\": \"迭代\"}]"]
        let bodies = BodiesBox()
        let translator = LLMTranslator(configuration: configuration, apiKey: "test-key") { request in
            let text = replies[bodies.values.count]
            bodies.values.append("")
            let data = try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": text]]])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let terms = try await translator.proposeTerms(
            for: [caption("We use Kubernetes", "我们用 Kubernetes"), caption("Plan the sprint", "规划迭代")],
            maxChunkCharacters: 40
        )

        XCTAssertEqual(terms.map(\.source), ["Kubernetes", "sprint"])
    }

    private func translator(replying text: String) -> LLMTranslator {
        let responseJSON = try! JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": text]]])
        return LLMTranslator(configuration: configuration, apiKey: "test-key") { request in
            (responseJSON, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func caption(_ english: String, _ chinese: String) -> Caption {
        Caption(id: UUID(), english: english, chinese: chinese, isProvisional: false, createdAt: .now)
    }
}

private final class BodyBox: @unchecked Sendable {
    var value: String?
}

private final class BodiesBox: @unchecked Sendable {
    var values: [String] = []
}
