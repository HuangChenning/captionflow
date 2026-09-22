import Foundation

protocol EnglishASR {
    func transcribe(samples: [Float]) async throws -> String
}

func normalizeEnglishTranscript(_ transcript: String) -> String {
    transcript.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Whisper emits bracketed tags like "[Music]" or "(music playing)" for non-speech
/// audio (e.g. background music) instead of leaving the transcript empty.
func isNonSpeechTranscript(_ transcript: String) -> Bool {
    guard !transcript.isEmpty else { return false }
    let isBracketed = (transcript.hasPrefix("[") && transcript.hasSuffix("]"))
        || (transcript.hasPrefix("(") && transcript.hasSuffix(")"))
    let isOnlyMusicNotes = transcript.allSatisfy { "♪♫ ".contains($0) }
    return isBracketed || isOnlyMusicNotes
}
