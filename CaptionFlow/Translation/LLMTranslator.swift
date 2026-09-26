import Foundation

enum LLMTranslatorError: Error, Equatable {
    case emptyAPIKey
    case httpStatus(Int)
    case emptyResponse
    case malformedTermList
}

struct LLMTranslator: Translator, CaptionRefiner {
    typealias RequestPerformer = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let configuration: LLMConfiguration
    private let apiKey: String
    private let style: LLMAPIStyle
    private let targetLanguageName: String
    private let glossary: [GlossaryEntry]
    private let performRequest: RequestPerformer

    init(
        configuration: LLMConfiguration,
        apiKey: String,
        style: LLMAPIStyle = .anthropic,
        targetLanguageName: String = TargetLanguage.simplifiedChinese.displayName,
        glossary: [GlossaryEntry] = [],
        performRequest: @escaping RequestPerformer = { try await URLSession.shared.data(for: $0) }
    ) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.style = style
        self.targetLanguageName = targetLanguageName
        self.glossary = glossary
        self.performRequest = performRequest
    }

    func translate(_ text: String) async throws -> String {
        try await send(text + glossarySection(for: text))
    }

    func refine(english: String, localDraft: String?) async throws -> String {
        var prompt = "English source:\n\(english)"
        if let localDraft {
            prompt += "\n\nLocal draft translation (correct it if needed):\n\(localDraft)"
        }
        prompt += glossarySection(for: english)
        prompt += "\n\nReply with only the final subtitle text."
        return try await send(prompt)
    }

    /// 让 LLM 从整场会话中列出需要统一译法的术语。只返回 LLM 的提议，是否采用由用户决定。
    func proposeTerms(for captions: [Caption]) async throws -> [GlossaryEntry] {
        let transcript = captions.map { caption in
            caption.chinese.map { "EN: \(caption.english)\nTranslation: \($0)" } ?? "EN: \(caption.english)"
        }.joined(separator: "\n")
        let prompt = """
        Below is an English speech transcript with its subtitles. List domain terms, product names, \
        and proper nouns whose translation should stay consistent in future subtitles. \
        Use the exact English spelling from the transcript.
        Reply with only a JSON array like [{"source": "English term", "target": "translation"}]. \
        Reply [] if there are none.

        Transcript:
        \(transcript)
        """
        let reply = try await send(prompt)
        // 模型可能在 JSON 前后加说明文字，只取第一个 [ 到最后一个 ] 之间的内容。
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end,
              let terms = try? JSONDecoder().decode([ProposedTerm].self, from: Data(reply[start...end].utf8)) else {
            throw LLMTranslatorError.malformedTermList
        }
        return terms.map { GlossaryEntry(source: $0.source, target: $0.target) }
    }

    /// 只附带原文里出现过的已确认术语，词库变大时不会撑大每个请求。
    private func glossarySection(for english: String) -> String {
        let terms = glossary
            .filter { english.range(of: $0.source, options: .caseInsensitive) != nil }
            .map { "\($0.source)=\($0.target)" }
        guard !terms.isEmpty else { return "" }
        return "\n\nApproved glossary (always use these translations):\n" + terms.joined(separator: "\n")
    }

    private func send(_ text: String) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMTranslatorError.emptyAPIKey }

        let request: URLRequest
        switch style {
        case .anthropic:
            request = try makeAnthropicRequest(text: text)
        case .openAICompatible:
            request = try makeOpenAIRequest(text: text)
        }

        let (data, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMTranslatorError.httpStatus(status)
        }

        switch style {
        case .anthropic:
            return try parseAnthropicResponse(data)
        case .openAICompatible:
            return try parseOpenAIResponse(data)
        }
    }

    private var systemInstruction: String {
        "\(configuration.instruction)\n\nTarget language: \(targetLanguageName)."
    }

    private func makeAnthropicRequest(text: String) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/messages"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(
            AnthropicMessagesRequest(
                model: configuration.model,
                maxTokens: 1024,
                messages: [AnthropicMessage(role: "user", content: "\(systemInstruction)\n\n\(text)")]
            )
        )
        return request
    }

    private func parseAnthropicResponse(_ data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        guard let translated = decoded.content.first(where: { $0.type == "text" })?.text,
              !translated.isEmpty else {
            throw LLMTranslatorError.emptyResponse
        }
        return translated
    }

    private func makeOpenAIRequest(text: String) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatRequest(
                model: configuration.model,
                messages: [
                    OpenAIMessage(role: "system", content: systemInstruction),
                    OpenAIMessage(role: "user", content: text)
                ]
            )
        )
        return request
    }

    private func parseOpenAIResponse(_ data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let translated = decoded.choices.first?.message.content,
              !translated.isEmpty else {
            throw LLMTranslatorError.emptyResponse
        }
        return translated
    }
}

private struct ProposedTerm: Decodable {
    let source: String
    let target: String
}

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}

private struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [ContentBlock]
}

private struct ContentBlock: Decodable {
    let type: String
    let text: String?
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIMessage
}
