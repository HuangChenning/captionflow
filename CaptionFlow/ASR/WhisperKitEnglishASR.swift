import Foundation
import WhisperKit

struct WhisperKitEnglishASR: EnglishASR {
    typealias Transcriber = @Sendable ([Float]) async throws -> String

    private let transcriber: Transcriber

    init(whisperKit: WhisperKit, language: String = "en") {
        self.transcriber = { samples in
            let options = DecodingOptions(task: .transcribe, language: language)
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            return results.map(\.text).joined()
        }
    }

    init(transcriber: @escaping Transcriber) {
        self.transcriber = transcriber
    }

    static func load(modelVariant: String = "base.en") async throws -> WhisperKitEnglishASR {
        let whisperKit = try await WhisperKit(WhisperKitConfig(model: modelVariant))
        return WhisperKitEnglishASR(whisperKit: whisperKit)
    }

    func transcribe(samples: [Float]) async throws -> String {
        normalizeEnglishTranscript(try await transcriber(samples))
    }
}
