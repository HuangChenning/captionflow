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
        XCTAssertNil(pipeline.captions[0].refinement, "without a refiner the overlay must not claim an LLM refinement")
    }

    /// 没有可用翻译时仍要显示英文字幕，而不是停止或一直等待译文。
    func testWithoutTranslatorShowsEnglishOnlyAndKeepsRunning() async throws {
        let pipeline = CaptionPipeline(
            audioSource: FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]]),
            asr: FakeASR { _ in "hello" },
            translator: nil,
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertEqual(pipeline.state, .running)
        XCTAssertEqual(pipeline.captions.map(\.english), ["hello"])
        XCTAssertNil(pipeline.captions[0].chinese)
        XCTAssertFalse(pipeline.captions[0].isProvisional, "the caption is final; the overlay must not show a pending translation")
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
        XCTAssertEqual(pipeline.captions[0].refinement, .refining, "the user must be able to tell the shown text is a local draft")

        gate.open()
        for task in pipeline.refineTasks.values { await task.value }

        XCTAssertEqual(pipeline.captions[0].chinese, "LLM 译文", "the LLM result must replace the local draft")
        XCTAssertFalse(pipeline.captions[0].isProvisional)
        XCTAssertEqual(pipeline.captions[0].refinement, .refined)
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
        XCTAssertEqual(pipeline.captions[0].refinement, .failed, "a kept local draft must not look like a refined result")
    }

    /// 会话中翻译出错时保留英文字幕继续运行：翻译不可用不应让用户连英文也看不到。
    func testTranslationErrorKeepsEnglishAndLaterSpeechRecovers() async throws {
        struct StubError: LocalizedError { var errorDescription: String? { "资源已被移除" } }
        let pipeline = CaptionPipeline(
            audioSource: FakeAudioSource(chunks: [[1, 1, 1, 1], [2, 2, 2, 2]]),
            asr: FakeASR { samples in samples[0] == 1 ? "first" : "second" },
            translator: FakeTranslator { text in
                if text == "first" { throw StubError() }
                return "第二句"
            },
            minChunkDuration: 1,
            sampleRate: 4
        )
        var errorsSeen: [String?] = []
        let observation = pipeline.$translationError.sink { errorsSeen.append($0) }
        defer { observation.cancel() }

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertEqual(pipeline.state, .running)
        XCTAssertNil(pipeline.captions[0].chinese)
        XCTAssertFalse(pipeline.captions[0].isProvisional)
        XCTAssertEqual(pipeline.captions[1].chinese, "第二句")
        XCTAssertTrue(errorsSeen.contains("资源已被移除"), "the failure reason must be surfaced to the overlay")
        XCTAssertNil(pipeline.translationError, "a later successful translation clears the error")
    }

    func testLocalAndRefinerBothFailingKeepsEnglishAndKeepsRunning() async throws {
        struct StubError: Error {}
        let pipeline = CaptionPipeline(
            audioSource: FakeAudioSource(chunks: [[0.1, 0.2, 0.3, 0.4]]),
            asr: FakeASR { _ in "hello" },
            translator: FakeTranslator { _ in throw StubError() },
            refiner: FakeTranslator { _ in throw StubError() },
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value
        for task in pipeline.refineTasks.values { await task.value }

        XCTAssertEqual(pipeline.state, .running)
        XCTAssertNil(pipeline.captions[0].chinese)
        XCTAssertFalse(pipeline.captions[0].isProvisional)
        XCTAssertNotNil(pipeline.translationError)
    }

    /// 本地资源在会话中下载完成后，之后的语音应使用新翻译，而不必重新开始字幕。
    func testUpdateTranslationAppliesToLaterSpeech() async throws {
        let box = PipelineBox()
        let pipeline = CaptionPipeline(
            audioSource: FakeAudioSource(chunks: [[1, 1, 1, 1], [2, 2, 2, 2]]),
            asr: FakeASR { samples in
                if samples[0] == 2 {
                    await MainActor.run {
                        box.pipeline?.updateTranslation(translator: FakeTranslator { _ in "本地译文" }, refiner: nil)
                    }
                    return "second"
                }
                return "first"
            },
            translator: nil,
            minChunkDuration: 1,
            sampleRate: 4
        )
        box.pipeline = pipeline

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertNil(pipeline.captions[0].chinese, "captions before the switch stay English-only")
        XCTAssertEqual(pipeline.captions[1].chinese, "本地译文")
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

    // 静音窗口若送进 Whisper 会得到 "you" 等幻觉文本，并为每个窗口触发一次翻译和 LLM 请求。
    func testSilentAudioIsNotTranscribed() async throws {
        let audioSource = FakeAudioSource(chunks: [[0, 0.001, -0.001, 0]])
        let asr = FakeASR { _ in
            XCTFail("must not transcribe silence")
            return "you"
        }
        let pipeline = CaptionPipeline(
            audioSource: audioSource,
            asr: asr,
            translator: FakeTranslator { _ in "你" },
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertTrue(pipeline.captions.isEmpty)
    }

    // 门限只挡静音，不能把音量较低的语音也丢掉。
    func testQuietSpeechAfterSilenceIsStillTranscribed() async throws {
        let audioSource = FakeAudioSource(chunks: [[0, 0, 0, 0], [0.02, -0.02, 0.02, -0.02]])
        var transcribed: [[Float]] = []
        let asr = FakeASR { samples in
            transcribed.append(samples)
            return "hello"
        }
        let pipeline = CaptionPipeline(
            audioSource: audioSource,
            asr: asr,
            translator: FakeTranslator { _ in "你好" },
            minChunkDuration: 1,
            sampleRate: 4
        )

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertEqual(transcribed, [[0.02, -0.02, 0.02, -0.02]])
        XCTAssertEqual(pipeline.captions.map(\.english), ["hello"])
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

@MainActor
private final class PipelineBox: @unchecked Sendable {
    var pipeline: CaptionPipeline?
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
