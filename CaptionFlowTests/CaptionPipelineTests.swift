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

    func testLocalDraftShowsFirstThenRefinerReplacesIt() async throws {
        let gate = Gate()
        let pipeline = CaptionPipeline(
            audioSource: FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]]),
            asr: FakeASR { _ in "hello" },
            translator: FakeTranslator { _ in "本地译文" },
            refiner: FakeTranslator { _ in
                await gate.wait()
                return "LLM 译文"
            },
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertEqual(pipeline.captions[0].chinese, "本地译文", "the local translation must appear without waiting for the LLM")
        XCTAssertTrue(pipeline.captions[0].isProvisional)

        gate.open()
        for task in pipeline.refineTasks.values { await task.value }

        XCTAssertEqual(pipeline.captions[0].chinese, "LLM 译文", "the LLM result must replace the local draft")
        XCTAssertFalse(pipeline.captions[0].isProvisional)
    }

    /// 精修要拿到本地初译，才能纠正它而不是从头重新翻译。
    func testRefinerReceivesLocalDraft() async throws {
        let pipeline = CaptionPipeline(
            audioSource: FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]]),
            asr: FakeASR { _ in "the minutes" },
            translator: FakeTranslator { _ in "分钟" },
            refiner: FakeRefiner { english, draft in
                XCTAssertEqual(english, "the minutes")
                XCTAssertEqual(draft, "分钟")
                return "会议纪要"
            },
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value
        for task in pipeline.refineTasks.values { await task.value }

        XCTAssertEqual(pipeline.captions[0].chinese, "会议纪要")
    }

    func testStuckRefinerDoesNotBlockLaterSpeech() async throws {
        let pipeline = CaptionPipeline(
            audioSource: FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4], [0.5, 0.6, 0.7, 0.8]]),
            asr: FakeASR { _ in "hello" },
            translator: FakeTranslator { _ in "本地译文" },
            refiner: FakeTranslator { _ in
                try await Task.sleep(for: .seconds(60))
                return "never"
            },
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertEqual(pipeline.captions.map(\.chinese), ["本地译文", "本地译文"], "a slow LLM must not stop later speech from being captioned")
        await pipeline.stop()
        XCTAssertTrue(pipeline.refineTasks.isEmpty)
    }

    func testRefinerFailureKeepsLocalDraft() async throws {
        struct StubError: Error {}
        let pipeline = CaptionPipeline(
            audioSource: FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]]),
            asr: FakeASR { _ in "hello" },
            translator: FakeTranslator { _ in "本地译文" },
            refiner: FakeTranslator { _ in throw StubError() },
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value
        for task in pipeline.refineTasks.values { await task.value }

        XCTAssertEqual(pipeline.state, .running, "an LLM failure must not stop captions when a local translation exists")
        XCTAssertEqual(pipeline.captions[0].chinese, "本地译文")
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

extension FakeTranslator: CaptionRefiner {
    func refine(english: String, localDraft: String?) async throws -> String {
        try await handler(english)
    }
}

private struct FakeRefiner: CaptionRefiner {
    let handler: @Sendable (String, String?) async throws -> String

    func refine(english: String, localDraft: String?) async throws -> String {
        try await handler(english, localDraft)
    }
}

/// 让 refiner 停在 wait()，直到测试调用 open()。
private final class Gate: @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func wait() async {
        for await _ in stream { return }
    }

    func open() {
        continuation.yield()
    }
}
