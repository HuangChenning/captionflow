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

    /// appBundleID 只对系统音频生效：nil 为全部应用。
    func makeSource(appBundleID: String? = nil) -> AudioSource {
        switch self {
        case .microphone: return MicrophoneAudioSource()
        case .systemAudio: return SystemAudioSource(appBundleID: appBundleID)
        }
    }
}

/// 上次选择的音频源，启动时恢复。
struct SavedAudioSource: Equatable {
    static let kindKey = "audio.sourceKind"
    static let appBundleIDKey = "audio.systemAudioAppBundleID"

    var kind: AudioSourceKind
    /// 仅对系统音频有效；nil 为全部系统音频。
    var appBundleID: String?

    static func load(from defaults: UserDefaults = .standard) -> SavedAudioSource {
        let kind = defaults.string(forKey: kindKey).flatMap(AudioSourceKind.init(rawValue:)) ?? .microphone
        return SavedAudioSource(kind: kind, appBundleID: kind == .systemAudio ? defaults.string(forKey: appBundleIDKey) : nil)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(kind.rawValue, forKey: Self.kindKey)
        defaults.set(appBundleID, forKey: Self.appBundleIDKey)
    }
}
