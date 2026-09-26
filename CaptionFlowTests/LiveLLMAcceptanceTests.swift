import XCTest
@testable import CaptionFlow

/// 真机验收：打当前选中的大模型。CI 不设置开关，因此会跳过。
/// 打开方式：创建 /tmp/captionflow-live-llm 后再跑这一组测试。
@MainActor
final class LiveLLMAcceptanceTests: XCTestCase {
    private let resultURL = URL(fileURLWithPath: "/tmp/captionflow-acceptance-result.txt")

    override func setUp() async throws {
        try skipUnlessLive()
    }

    /// 带专有名词的一句被本地译错后，大模型要改对；下一句在这句精修结束前就要进入字幕，会话不能停。
    func testLiveProperNounSampleCorrectsLocalDraftWithoutBlockingTheNextCaption() async throws {
        let glossary = [
            GlossaryEntry(source: "Lucas Rest", target: "卢卡斯·雷斯特"),
            GlossaryEntry(source: "Microsoft Build", target: "微软 Build 大会")
        ]
        let refiner = try makeLiveTranslator(glossary: glossary)
        let local = ObservingTranslator()
        let pipeline = CaptionPipeline(
            audioSource: TwoChunkAudioSource(),
            asr: ScriptedASR(),
            translator: local,
            refiner: refiner,
            minChunkDuration: 1,
            sampleRate: 4
        )
        local.pipeline = pipeline

        await pipeline.start()
        await pipeline.pumpTask?.value

        XCTAssertEqual(pipeline.captions.map(\.english), [
            "Looks rest will speak at Microsoft Build in Seattle",
            "The next session starts at noon"
        ])
        XCTAssertEqual(pipeline.state, .running, "a live refinement must not stop the session")
        XCTAssertEqual(
            local.firstRefinementWhenSecondStarted,
            .refining,
            "the next caption must start while the first sentence is still being refined"
        )

        for task in pipeline.refineTasks.values { await task.value }

        let corrected = try XCTUnwrap(pipeline.captions[0].chinese)
        let following = try XCTUnwrap(pipeline.captions[1].chinese)
        note("proper noun refined: \(corrected)")
        note("following caption: \(following)")
        XCTAssertEqual(pipeline.captions[0].refinement, .refined, "refinement failed, kept: \(corrected)")
        XCTAssertEqual(pipeline.captions[1].refinement, .refined, "the following caption was not refined: \(following)")
        XCTAssertTrue(corrected.contains("卢卡斯"), "expected the misheard name to be restored, got: \(corrected)")
        XCTAssertTrue(corrected.contains("微软"), "expected the approved event name, got: \(corrected)")
        XCTAssertFalse(corrected.contains("看起来休息"), "local draft was not corrected: \(corrected)")
        XCTAssertFalse(corrected.contains("制造"), "Build was still translated as 制造: \(corrected)")
        XCTAssertNotEqual(following, "下一场在中午开始")
    }

    /// 没点采纳的候选不能进词库。采纳之后，后面两句都要使用确认过的译法，而不是本地的错译。
    func testLiveConfirmedTermIsReusedAndUnconfirmedCandidateStaysOutOfGlossary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let glossaryStore = GlossaryStore(fileURL: directory.appendingPathComponent("glossary.json"))
        let candidateStore = TermCandidateStore(fileURL: directory.appendingPathComponent("term-candidates.json"))
        let ignoredStore = IgnoredTermStore(fileURL: directory.appendingPathComponent("ignored-terms.json"))
        let extractor = try makeLiveTranslator(glossary: [])
        let session = CaptionSession(
            id: UUID(),
            createdAt: .now,
            captions: [
                Caption(id: UUID(), english: "We deployed the service on Kubernetes yesterday", chinese: "我们昨天把服务部署到了 Kubernetes", isProvisional: false, createdAt: .now),
                Caption(id: UUID(), english: "Plan the sprint and groom the backlog", chinese: "规划冲刺并整理积压", isProvisional: false, createdAt: .now)
            ]
        )

        let proposals = try await extractor.proposeTerms(for: session.captions)
        let found = try TermCandidate.record(
            proposals,
            from: session,
            candidateStore: candidateStore,
            glossaryStore: glossaryStore,
            ignoredStore: ignoredStore
        )
        note("proposed: \(found.map { "\($0.source)=\($0.target) (\($0.occurrences ?? 0))" }.joined(separator: ", "))")
        XCTAssertEqual(try glossaryStore.load(), [], "unconfirmed candidates must not be written to the glossary")

        try glossaryStore.save([GlossaryEntry(source: "minutes", target: "会议纪要")])
        let refiner = try makeLiveTranslator(glossary: try glossaryStore.load())
        let later = [
            ("Please send the minutes to the team", "请把分钟发给团队"),
            ("I reviewed the minutes before the meeting", "我在开会前复习了分钟")
        ]
        var previous: String?
        for (english, draft) in later {
            let refined = try await refiner.refine(english: english, localDraft: draft, previousEnglish: previous)
            note("confirmed term \(english) -> \(refined)")
            XCTAssertTrue(refined.contains("会议纪要"), "\(english) refined to: \(refined)")
            XCTAssertFalse(refined.contains("分钟"), "\(english) still used the wrong local word: \(refined)")
            previous = english
        }
    }

    private func skipUnlessLive() throws {
        let enabled = ProcessInfo.processInfo.environment["CAPTIONFLOW_LIVE_LLM"] == "1"
            || FileManager.default.fileExists(atPath: "/tmp/captionflow-live-llm")
        try XCTSkipUnless(enabled, "create /tmp/captionflow-live-llm to run the live model acceptance")
    }

    private func makeLiveTranslator(glossary: [GlossaryEntry]) throws -> LLMTranslator {
        let profiles = LLMProfileStore.load()
        guard let selected = LLMProfileStore.selectedID,
              let profile = profiles.first(where: { $0.id == selected }),
              let configuration = LLMConfiguration(
                baseURL: profile.baseURL,
                model: profile.model,
                instruction: UserDefaults.standard.string(forKey: "llm.instruction")
                    ?? "Translate English speech into concise, natural Simplified Chinese subtitles."
              ) else {
            XCTFail("no selected LLM profile")
            throw LiveAcceptanceError.notConfigured
        }
        let apiKey = try KeychainStore(service: "com.taihongteng.CaptionFlow").secret(for: profile.id.uuidString) ?? ""
        guard !apiKey.isEmpty else {
            XCTFail("selected profile has no API key")
            throw LiveAcceptanceError.notConfigured
        }
        note("model: \(profile.model)")
        return LLMTranslator(
            configuration: configuration,
            apiKey: apiKey,
            style: profile.apiStyle,
            glossary: glossary
        )
    }

    private func note(_ line: String) {
        let existing = (try? String(contentsOf: resultURL, encoding: .utf8)) ?? ""
        try? (existing + line + "\n").write(to: resultURL, atomically: true, encoding: .utf8)
    }
}

private enum LiveAcceptanceError: Error {
    case notConfigured
}

@MainActor
private final class ObservingTranslator: Translator {
    weak var pipeline: CaptionPipeline?
    private(set) var firstRefinementWhenSecondStarted: Caption.Refinement?

    func translate(_ text: String) async throws -> String {
        if text.contains("next session") {
            firstRefinementWhenSecondStarted = pipeline?.captions.first?.refinement
        }
        if text.contains("Looks rest") { return "看起来休息会在西雅图制造" }
        return "下一场在中午开始"
    }
}

private final class TwoChunkAudioSource: AudioSource, @unchecked Sendable {
    func start() async throws -> AsyncStream<[Float]> {
        AsyncStream { continuation in
            continuation.yield([1, 1, 1, 1])
            continuation.yield([2, 2, 2, 2])
            continuation.finish()
        }
    }

    func stop() async {}
}

private struct ScriptedASR: EnglishASR {
    func transcribe(samples: [Float]) async throws -> String {
        samples.first == 1
            ? "Looks rest will speak at Microsoft Build in Seattle"
            : "The next session starts at noon"
    }
}

