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
            try await $0.refine(english: "Please send the Minutes", localDraft: "请发送分钟", previousEnglish: nil)
        }

        XCTAssertTrue(body.contains("Please send the Minutes"))
        XCTAssertTrue(body.contains("请发送分钟"), "the LLM must see the local draft so it can correct it")
        XCTAssertTrue(body.contains("minutes=会议纪要"), "matching is case-insensitive")
    }

    /// 只附带原文里出现的术语：其余词条对这一句没有用，还会增加请求长度。
    func testRefinementOmitsGlossaryTermsNotInSource() async throws {
        let body = try await capturedRequestBody(glossary: [GlossaryEntry(source: "minutes", target: "会议纪要")]) {
            try await $0.refine(english: "hello", localDraft: nil, previousEnglish: nil)
        }

        XCTAssertFalse(body.contains("会议纪要"))
        XCTAssertFalse(body.contains("glossary"))
        XCTAssertFalse(body.contains("Possible names"))
    }

    /// 识别把人名听错时原文对不上词条（"Lucas Rest" 听成 "Looks rest"）。
    /// 精修要看到词库里的专有名词，但普通术语和全大写缩写不能跟着附上，否则会被套到无关的句子。
    func testRefinementOffersUnmatchedProperNounsAsPossibleMishearings() async throws {
        let body = try await capturedRequestBody(glossary: [
            GlossaryEntry(source: "Lucas Rest", target: "卢卡斯·雷斯特"),
            GlossaryEntry(source: "minutes", target: "会议纪要"),
            GlossaryEntry(source: "API", target: "接口")
        ]) {
            try await $0.refine(english: "Looks rest will speak", localDraft: "看起来休息会发言", previousEnglish: nil)
        }

        XCTAssertTrue(body.contains("Possible names"))
        XCTAssertTrue(body.contains("Lucas Rest=卢卡斯·雷斯特"))
        XCTAssertTrue(body.contains("sounds like it"), "the model must not force a name that does not fit")
        XCTAssertFalse(body.contains("会议纪要"))
        XCTAssertFalse(body.contains("API=接口"))
        XCTAssertFalse(body.contains("Approved glossary"))
    }

    /// 原文里已经出现的专有名词走“必须使用”的词库，不再放进可能听错的名字列表。
    func testRefinementKeepsExactProperNounInApprovedGlossaryOnly() async throws {
        let body = try await capturedRequestBody(glossary: [
            GlossaryEntry(source: "Lucas Rest", target: "卢卡斯·雷斯特")
        ]) {
            try await $0.refine(english: "Lucas Rest will speak", localDraft: nil, previousEnglish: nil)
        }

        XCTAssertTrue(body.contains("Approved glossary"))
        XCTAssertTrue(body.contains("Lucas Rest=卢卡斯·雷斯特"))
        XCTAssertFalse(body.contains("Possible names"))
    }

    /// 名字列表要有上限，词库变大时精修请求不能跟着无限变长。
    func testRefinementCapsPossibleNames() async throws {
        let names = (0...LLMTranslator.maxPossibleNames).map { index in
            GlossaryEntry(source: String(format: "Nomen%02d", index), target: "人名\(index)")
        }
        let body = try await capturedRequestBody(glossary: names) {
            try await $0.refine(english: "hello", localDraft: nil, previousEnglish: nil)
        }
        let kept = String(format: "Nomen%02d", LLMTranslator.maxPossibleNames - 1)
        let dropped = String(format: "Nomen%02d=人名%d", LLMTranslator.maxPossibleNames, LLMTranslator.maxPossibleNames)

        XCTAssertTrue(body.contains("Nomen00=人名0"))
        XCTAssertTrue(body.contains(kept))
        XCTAssertFalse(body.contains(dropped))
    }

    /// 可能听错的名字只给精修。直接翻译不附带原文里没有出现的专有名词。
    func testTranslateDoesNotOfferUnmatchedProperNouns() async throws {
        let body = try await capturedRequestBody(glossary: [
            GlossaryEntry(source: "Lucas Rest", target: "卢卡斯·雷斯特")
        ]) {
            try await $0.translate("Looks rest will speak")
        }

        XCTAssertFalse(body.contains("Lucas Rest"))
        XCTAssertFalse(body.contains("Possible names"))
    }

    /// 仅 LLM 模式下没有精修步骤，术语要在直接翻译时生效。
    func testTranslateAlsoAppliesGlossary() async throws {
        let body = try await capturedRequestBody(glossary: [GlossaryEntry(source: "minutes", target: "会议纪要")]) {
            try await $0.translate("the minutes")
        }

        XCTAssertTrue(body.contains("minutes=会议纪要"))
    }

    /// 上一条字幕只作上下文，要明确告诉模型不要把它也翻出来，否则字幕会重复上一句。
    func testRefinementIncludesPreviousCaptionAsContextOnly() async throws {
        let body = try await capturedRequestBody(glossary: []) {
            try await $0.refine(english: "or their execution", localDraft: nil, previousEnglish: "the strategies of battle")
        }

        XCTAssertTrue(body.contains("the strategies of battle"))
        XCTAssertTrue(body.contains("do not translate it"))
    }

    /// 识别结果常有听错的词，模型若逐字翻译，"difference" 会译成“不同”而不是“尊重”。
    func testRefinementWarnsThatSourceMayBeMisheard() async throws {
        let body = try await capturedRequestBody(glossary: []) {
            try await $0.refine(english: "give me difference", localDraft: nil, previousEnglish: nil)
        }

        XCTAssertTrue(body.contains("misheard"))
    }

    func testRefinementWithoutPreviousCaptionHasNoContextSection() async throws {
        let body = try await capturedRequestBody(glossary: []) {
            try await $0.refine(english: "hello", localDraft: nil, previousEnglish: nil)
        }

        XCTAssertFalse(body.contains("Previous subtitle"))
    }

    /// 默认开启思考的模型会把 max_tokens 用在思考上、不返回译文（2026-09-26 验收中 10 句失败 5 句），所以请求要关闭思考。
    func testAnthropicRequestDisablesThinking() async throws {
        let body = try await capturedRequestBody(glossary: []) {
            try await $0.refine(english: "hello", localDraft: nil, previousEnglish: nil)
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

    /// 优化一条候选时要能改听错的英文，并且只给出建议，不把术语写进请求里的已确认词库段。
    func testOptimizeTermCorrectsMisheardEnglishFromTheExample() async throws {
        let body = BodyBox()
        let reply = #"Suggestion: {"source": "Rook's Rest", "target": "鸦栖堡"}"#
        let responseJSON = try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": reply]]])
        let translator = LLMTranslator(configuration: configuration, apiKey: "test-key", glossary: [GlossaryEntry(source: "minutes", target: "会议纪要")]) { request in
            body.value = String(decoding: request.httpBody!, as: UTF8.self)
            return (responseJSON, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let improved = try await translator.optimizeTerm(
            source: "Looks rest",
            target: "看来休息",
            example: "The rooks rest are gone."
        )

        XCTAssertEqual(improved.source, "Rook's Rest")
        XCTAssertEqual(improved.target, "鸦栖堡")
        let sent = try XCTUnwrap(body.value)
        XCTAssertTrue(sent.contains("The rooks rest are gone."))
        XCTAssertTrue(sent.contains("misheard"))
        XCTAssertFalse(sent.contains("Approved glossary"))
    }

    func testOptimizeTermThrowsWhenReplyIsNotOneTerm() async throws {
        let translator = translator(replying: "I would translate this as 休息.")

        do {
            _ = try await translator.optimizeTerm(source: "rest", target: "", example: "")
            XCTFail("expected LLMTranslatorError.malformedTermList")
        } catch LLMTranslatorError.malformedTermList {
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
        XCTAssertTrue(body.contains("recurring phrases"), "extraction must include phrases, not only proper nouns")
        XCTAssertTrue(body.contains("fixed expressions"))
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
