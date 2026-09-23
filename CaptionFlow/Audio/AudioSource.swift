import Foundation

enum AudioSourceError: LocalizedError {
    case unsupportedFormat
    case noDisplayAvailable
    case appNotRunning
    case screenCapturePermissionDenied

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "不支持的音频格式。"
        case .noDisplayAvailable: return "找不到可用于采集系统音频的显示器。"
        case .appNotRunning: return "所选应用没有在运行，请重新选择音频源。"
        case .screenCapturePermissionDenied: return "没有「录屏与系统录音」权限，授权后需重新打开 CaptionFlow。"
        }
    }
}

protocol AudioSource: AnyObject, Sendable {
    /// Starts capture and returns a stream of mono 16kHz Float32 sample chunks.
    func start() async throws -> AsyncStream<[Float]>
    func stop() async
}
