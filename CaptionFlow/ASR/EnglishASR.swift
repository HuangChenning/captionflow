import Foundation

protocol EnglishASR {
    func transcribe(samples: [Float]) async throws -> String
}

/// 设置里选择的语音识别引擎。
enum SpeechRecognitionEngine: String, CaseIterable, Identifiable {
    case whisper
    case apple

    static let key = "asr.engine"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper: return "Whisper base.en（App 自带模型）"
        case .apple: return "苹果系统识别（需要 macOS 26）"
        }
    }
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
