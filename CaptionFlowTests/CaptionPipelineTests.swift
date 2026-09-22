import XCTest
@testable import CaptionFlow

@MainActor
final class CaptionPipelineTests: XCTestCase {
    func testStartTranscribesAndTranslatesBufferedAudio() async throws {
        let audioSource = FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]])
        let asr = FakeASR { samples in
            XCTAssertEqual(samples, [0.1, 0.2, 0.3, 0.4])
            return "hello"
        }
        let translator = FakeTranslator { text in
            XCTAssertEqual(text, "hello")
            return "你好"
        }
        let pipeline = CaptionPipeline(
            audioSource: audioSource,
            asr: asr,
            translator: translator,
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertEqual(pipeline.state, .running)
        XCTAssertEqual(pipeline.captions.count, 1)
        XCTAssertEqual(pipeline.captions[0].english, "hello")
        XCTAssertEqual(pipeline.captions[0].chinese, "你好")
        XCTAssertFalse(pipeline.captions[0].isProvisional)
    }

    func testBuffersAudioUntilMinimumChunkDurationReached() async throws {
        var transcribedSamples: [[Float]] = []
        let audioSource = FakeAudioSource(chunks: [[0.1, 0.2], [0.3, 0.4]])
        let asr = FakeASR { samples in
            transcribedSamples.append(samples)
            return "hello"
        }
        let translator = FakeTranslator { _ in "你好" }
        let pipeline = CaptionPipeline(
            audioSource: audioSource,
            asr: asr,
            translator: translator,
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertEqual(transcribedSamples, [[0.1, 0.2, 0.3, 0.4]])
    }

    func testEmptyTranscriptDoesNotProduceCaption() async throws {
        let audioSource = FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]])
        let asr = FakeASR { _ in "" }
        let translator = FakeTranslator { _ in
            XCTFail("must not translate an empty transcript")
            return ""
        }
        let pipeline = CaptionPipeline(
            audioSource: audioSource,
            asr: asr,
            translator: translator,
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertTrue(pipeline.captions.isEmpty)
    }

    func testNonSpeechTranscriptDoesNotProduceCaption() async throws {
        let audioSource = FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]])
        let asr = FakeASR { _ in "[Music]" }
        let translator = FakeTranslator { _ in
            XCTFail("must not translate a non-speech transcript")
            return ""
        }
        let pipeline = CaptionPipeline(
            audioSource: audioSource,
            asr: asr,
            translator: translator,
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertTrue(pipeline.captions.isEmpty)
    }

    func testTranscriptionErrorTransitionsToFailedAndStopsAudioSource() async throws {
        struct StubError: Error {}
        let audioSource = FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]])
        let asr = FakeASR { _ in throw StubError() }
        let translator = FakeTranslator { _ in "unused" }
        let pipeline = CaptionPipeline(
            audioSource: audioSource,
            asr: asr,
            translator: translator,
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        guard case .failed = pipeline.state else {
            XCTFail("expected failed state, got \(pipeline.state)")
            return
        }
        XCTAssertTrue(audioSource.stopCalled)
    }

    func testStopCancelsPumpAndStopsAudioSource() async throws {
        let audioSource = FakeAudioSource(chunks: [])
        let asr = FakeASR { _ in "hello" }
        let translator = FakeTranslator { _ in "你好" }
        let pipeline = CaptionPipeline(
            audioSource: audioSource,
            asr: asr,
            translator: translator,
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        XCTAssertEqual(pipeline.state, .running)

        await pipeline.stop()

        XCTAssertEqual(pipeline.state, .idle)
        XCTAssertTrue(audioSource.stopCalled)
    }
}

private final class FakeAudioSource: AudioSource, @unchecked Sendable {
    private let chunks: [[Float]]
    private(set) var stopCalled = false

    init(chunks: [[Float]]) {
        self.chunks = chunks
    }

    func start() async throws -> AsyncStream<[Float]> {
        let chunks = self.chunks
        return AsyncStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func stop() async {
        stopCalled = true
    }
}

private struct FakeASR: EnglishASR {
    let handler: (_ samples: [Float]) async throws -> String

    func transcribe(samples: [Float]) async throws -> String {
        try await handler(samples)
    }
}

private struct FakeTranslator: Translator {
    let handler: @Sendable (String) async throws -> String

    func translate(_ text: String) async throws -> String {
        try await handler(text)
    }
}
