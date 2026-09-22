import XCTest
import AVFoundation
@testable import CaptionFlow

final class AudioResamplerTests: XCTestCase {
    func testResampleIsNearIdentityForMatchingFormat() throws {
        let format = AudioResampler.targetFormat
        let values: [Float] = [0.1, -0.2, 0.3, -0.4]
        let buffer = try makeBuffer(format: format, values: values)

        let converter = try XCTUnwrap(AVAudioConverter(from: format, to: format))
        let result = AudioResampler.resample(buffer, using: converter)

        XCTAssertEqual(result?.count, values.count)
        for (index, value) in values.enumerated() {
            XCTAssertEqual(result?[index] ?? .nan, value, accuracy: 0.001)
        }
    }

    func testResampleConvertsSampleRateToTarget() throws {
        let sourceFormat = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)
        )
        let frameCount = 48_000 // 1s at 48kHz
        let values = (0..<frameCount).map { Float(sin(Double($0) * 0.1)) }
        let buffer = try makeBuffer(format: sourceFormat, values: values)

        let converter = try XCTUnwrap(AVAudioConverter(from: sourceFormat, to: AudioResampler.targetFormat))
        let result = try XCTUnwrap(AudioResampler.resample(buffer, using: converter))

        // 1s of audio downsampled to 16kHz should be close to 16000 samples; a single
        // one-shot conversion undershoots slightly due to the converter's filter latency.
        XCTAssertEqual(Double(result.count), 16_000, accuracy: 500)
    }

    private func makeBuffer(format: AVAudioFormat, values: [Float]) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)))
        buffer.frameLength = AVAudioFrameCount(values.count)
        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for (index, value) in values.enumerated() {
            channelData[0][index] = value
        }
        return buffer
    }
}
