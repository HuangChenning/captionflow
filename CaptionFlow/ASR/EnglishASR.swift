import Foundation

protocol EnglishASR {
    func transcribe(samples: [Float]) async throws -> String
}

func normalizeEnglishTranscript(_ transcript: String) -> String {
    transcript.trimmingCharacters(in: .whitespacesAndNewlines)
}
