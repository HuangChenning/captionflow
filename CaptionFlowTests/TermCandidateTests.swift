import XCTest
@testable import CaptionFlow

final class TermCandidateTests: XCTestCase {
    private let sessionDate = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(_ sentences: [String]) -> CaptionSession {
        CaptionSession(
            id: UUID(),
            createdAt: sessionDate,
            captions: sentences.map { Caption(id: UUID(), english: $0, chinese: nil, isProvisional: false, createdAt: .now) }
        )
    }

    /// 示例句必须来自会话原文，用户才能据此判断候选是否合理。
    func testCandidateCarriesSourceSessionAndExampleFromTranscript() {
        let candidates = TermCandidate.make(
            from: [GlossaryEntry(source: " kubernetes ", target: " Kubernetes ")],
            session: session(["Hello everyone", "We deployed it on Kubernetes yesterday"]),
            excluding: []
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].source, "kubernetes")
        XCTAssertEqual(candidates[0].target, "Kubernetes")
        XCTAssertEqual(candidates[0].example, "We deployed it on Kubernetes yesterday")
        XCTAssertEqual(candidates[0].sessionDate, sessionDate)
    }

    /// 原文里没有出现的术语是 LLM 编造的，不能拿给用户确认。
    func testDropsTermsThatDoNotAppearInTranscript() {
        let candidates = TermCandidate.make(
            from: [GlossaryEntry(source: "Terraform", target: "Terraform")],
            session: session(["We deployed it on Kubernetes"]),
            excluding: []
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    /// 已确认或已在候选列表里的术语不重复提出，同一次回复里的重复项只保留一个。
    func testDropsExistingDuplicateAndBlankTerms() {
        let candidates = TermCandidate.make(
            from: [
                GlossaryEntry(source: "Minutes", target: "会议纪要"),
                GlossaryEntry(source: "roadmap", target: "路线图"),
                GlossaryEntry(source: "sprint", target: "迭代"),
                GlossaryEntry(source: "Sprint", target: "冲刺"),
                GlossaryEntry(source: "backlog", target: " ")
            ],
            session: session(["Review the minutes, the roadmap, the sprint and the backlog"]),
            excluding: ["minutes", "ROADMAP"]
        )

        XCTAssertEqual(candidates.map(\.source), ["sprint"])
        XCTAssertEqual(candidates.map(\.target), ["迭代"])
    }

    /// 候选单独存放：保存候选不能让它们出现在翻译使用的已确认词库里。
    func testCandidateStoreRoundTripsWithoutTouchingGlossary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidateStore = TermCandidateStore(fileURL: directory.appendingPathComponent("term-candidates.json"))
        let glossaryStore = GlossaryStore(fileURL: directory.appendingPathComponent("glossary.json"))
        let candidate = TermCandidate(source: "sprint", target: "迭代", example: "the sprint", sessionDate: sessionDate)

        try candidateStore.save([candidate])

        XCTAssertEqual(try candidateStore.load(), [candidate])
        XCTAssertEqual(try glossaryStore.load(), [])
    }
}
