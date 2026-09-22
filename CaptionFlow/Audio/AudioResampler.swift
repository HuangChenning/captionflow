import AVFoundation

enum AudioResampler {
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// Converts `buffer` to `AudioResampler.targetFormat` using `converter` and returns its samples.
    static func resample(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> [Float]? {
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)
        ) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }
}
