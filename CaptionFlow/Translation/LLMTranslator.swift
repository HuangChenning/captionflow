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
    private let performRequest: RequestPerformer

    init(
        configuration: LLMConfiguration,
        apiKey: String,
        performRequest: @escaping RequestPerformer = { try await URLSession.shared.data(for: $0) }
    ) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.performRequest = performRequest
    }

    func translate(_ text: String) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMTranslatorError.emptyAPIKey }

        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/messages"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(
            MessagesRequest(
                model: configuration.model,
                maxTokens: 1024,
                messages: [Message(role: "user", content: "\(configuration.instruction)\n\n\(text)")]
            )
        )

        let (data, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMTranslatorError.httpStatus(status)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let translated = decoded.content.first(where: { $0.type == "text" })?.text,
              !translated.isEmpty else {
            throw LLMTranslatorError.emptyResponse
        }
        return translated
    }
}

private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}

private struct Message: Codable {
    let role: String
    let content: String
}

private struct MessagesResponse: Decodable {
    let content: [ContentBlock]
}

private struct ContentBlock: Decodable {
    let type: String
    let text: String?
}
