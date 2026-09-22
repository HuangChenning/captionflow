import Foundation

enum AudioSourceError: Error {
    case unsupportedFormat
    case noDisplayAvailable
}

protocol AudioSource: AnyObject, Sendable {
    /// Starts capture and returns a stream of mono 16kHz Float32 sample chunks.
    func start() async throws -> AsyncStream<[Float]>
    func stop() async
}
