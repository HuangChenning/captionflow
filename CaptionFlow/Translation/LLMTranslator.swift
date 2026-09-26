import Foundation

enum LLMTranslatorError: Error, Equatable {
    case emptyAPIKey
    case httpStatus(Int)
    case emptyResponse
}

struct LLMTranslator: Translator {
    typealias RequestPerformer = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let configuration: LLMConfiguration
    private let apiKey: String
    private let style: LLMAPIStyle
    private let targetLanguageName: String
    private let performRequest: RequestPerformer

    init(
        configuration: LLMConfiguration,
        apiKey: String,
        style: LLMAPIStyle = .anthropic,
        targetLanguageName: String = TargetLanguage.simplifiedChinese.displayName,
        performRequest: @escaping RequestPerformer = { try await URLSession.shared.data(for: $0) }
    ) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.style = style
        self.targetLanguageName = targetLanguageName
        self.performRequest = performRequest
    }

    func translate(_ text: String) async throws -> String {
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

    func refine(english: String, localDraft: String, glossary: [GlossaryEntry]) async throws -> String {
        let terms = glossary.map { "\($0.source)=\($0.target)" }.joined(separator: "\n")
        return try await translate("""
        English source:
        \(english)

        Local Chinese draft:
        \(localDraft)

        Approved glossary:
        \(terms)
        """)
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
