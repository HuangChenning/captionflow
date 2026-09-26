import Foundation
import os

private let logger = Logger(subsystem: "com.taihongteng.CaptionFlow", category: "LLM")

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

    func refine(english: String, localDraft: String?, previousEnglish: String?) async throws -> String {
        var prompt = ""
        if let previousEnglish {
            prompt += "Previous subtitle, for context only (do not translate it):\n\(previousEnglish)\n\n"
        }
        prompt += "English source:\n\(english)"
        // 原文来自语音识别，常把词听错（"deference" 识别成 "difference"），让模型按语境理解原意。
        prompt += "\n\nThe English source is speech recognition output and may contain misheard words. "
            + "If a word does not fit the context, translate what the speaker most likely said."
        if let localDraft {
            prompt += "\n\nLocal draft translation (correct it if needed):\n\(localDraft)"
        }
        prompt += glossarySection(for: english)
        prompt += "\n\nReply with only the final subtitle text."
        return try await send(prompt)
    }

    /// 让 LLM 从整场会话中列出需要统一译法的术语。只返回 LLM 的提议，是否采用由用户决定。
    /// 长会话按字符数分段，每段单独请求，避免超出模型上下文；各段结果合并返回，重复项由调用方去掉。
    func proposeTerms(for captions: [Caption], maxChunkCharacters: Int = 6000) async throws -> [GlossaryEntry] {
        let lines = captions.map { caption in
            caption.chinese.map { "EN: \(caption.english)\nTranslation: \($0)" } ?? "EN: \(caption.english)"
        }
        var chunks: [[String]] = []
        var length = 0
        for line in lines {
            if chunks.isEmpty || (length + line.count > maxChunkCharacters && !chunks[chunks.count - 1].isEmpty) {
                chunks.append([])
                length = 0
            }
            chunks[chunks.count - 1].append(line)
            length += line.count
        }
        var terms: [GlossaryEntry] = []
        for chunk in chunks {
            terms += try await proposeTerms(inTranscript: chunk.joined(separator: "\n"))
        }
        return terms
    }

    private func proposeTerms(inTranscript transcript: String) async throws -> [GlossaryEntry] {
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
                thinking: AnthropicThinking(type: "disabled"),
                messages: [AnthropicMessage(role: "user", content: "\(systemInstruction)\n\n\(text)")]
            )
        )
        return request
    }

    private func parseAnthropicResponse(_ data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        guard let translated = decoded.content.first(where: { $0.type == "text" })?.text,
              !translated.isEmpty else {
            // 只记录结束原因和内容块类型，不记录字幕内容。
            let blocks = decoded.content.map(\.type).joined(separator: ",")
            logger.error("Anthropic reply has no text: stop_reason=\(decoded.stopReason ?? "nil", privacy: .public) blocks=[\(blocks, privacy: .public)]")
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
            logger.error("OpenAI-compatible reply has no text: finish_reason=\(decoded.choices.first?.finishReason ?? "nil", privacy: .public)")
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
    /// 字幕翻译不需要思考；默认开启思考的模型（如 deepseek-v4-flash）会把 max_tokens 用在思考上，返回没有译文的回复。
    let thinking: AnthropicThinking
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case thinking
        case messages
    }
}

private struct AnthropicThinking: Encodable {
    let type: String
}

private struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
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
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}
