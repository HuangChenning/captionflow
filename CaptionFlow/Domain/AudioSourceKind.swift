import Foundation

enum AudioSourceKind: String, CaseIterable, Identifiable {
    case microphone
    case systemAudio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        }
    }

    func makeSource() -> AudioSource {
        switch self {
        case .microphone: return MicrophoneAudioSource()
        case .systemAudio: return SystemAudioSource()
        }
    }
}
