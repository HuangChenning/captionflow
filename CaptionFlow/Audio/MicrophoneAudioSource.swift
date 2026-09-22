import AVFoundation

final class MicrophoneAudioSource: AudioSource {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<[Float]>.Continuation?

    func start() async throws -> AsyncStream<[Float]> {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: AudioResampler.targetFormat) else {
            throw AudioSourceError.unsupportedFormat
        }

        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        self.continuation = continuation

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let samples = AudioResampler.resample(buffer, using: converter) else { return }
            continuation.yield(samples)
        }

        engine.prepare()
        try engine.start()

        return stream
    }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }
}
