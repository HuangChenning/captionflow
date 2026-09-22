import AVFoundation
import ScreenCaptureKit

final class SystemAudioSource: NSObject, AudioSource, SCStreamOutput {
    private var stream: SCStream?
    private var continuation: AsyncStream<[Float]>.Continuation?
    private var converter: AVAudioConverter?

    func start() async throws -> AsyncStream<[Float]> {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw AudioSourceError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // No video is needed; keep the frame surface minimal to avoid wasted capture work.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        self.continuation = continuation

        let scStream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await scStream.startCapture()
        self.stream = scStream

        return stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        continuation?.finish()
        continuation = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let pcmBuffer = sampleBuffer.asPCMBuffer else { return }

        if converter == nil {
            converter = AVAudioConverter(from: pcmBuffer.format, to: AudioResampler.targetFormat)
        }
        guard let converter, let samples = AudioResampler.resample(pcmBuffer, using: converter) else { return }
        continuation?.yield(samples)
    }
}

private extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let audioFormat = AVAudioFormat(streamDescription: streamDescription) else {
            return nil
        }

        // AudioBufferList is variable-length for multi-channel non-interleaved audio;
        // withAudioBufferList sizes the allocation correctly, unlike a fixed-size struct.
        var pcmBuffer: AVAudioPCMBuffer?
        try? withAudioBufferList { audioBufferList, _ in
            pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, bufferListNoCopy: audioBufferList.unsafePointer)
        }

        pcmBuffer?.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        return pcmBuffer
    }
}
