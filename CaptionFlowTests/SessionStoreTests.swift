import XCTest
@testable import CaptionFlow

final class SessionStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSavedSessionReloadsAndExportsOnlyCaptionText() throws {
        let store = SessionStore(directory: directory)
        let caption = Caption(id: UUID(), english: "hello", chinese: "你好", isProvisional: false, createdAt: .now)

        let session = try store.save(captions: [caption])
        XCTAssertEqual(try store.loadSessions(), [session])

        let exportURL = directory.appendingPathComponent("captions.txt")
        try store.exportText(sessionID: session.id, to: exportURL)
        let text = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(text.contains("hello"))
        XCTAssertTrue(text.contains("你好"))
        XCTAssertFalse(text.contains("api-key"))
        XCTAssertFalse(text.contains(".wav"))
    }

    /// 打开一场会话后要能按英文或译文找到句子；没输入时仍看到全部，按原来的时间顺序。
    func testSearchMatchesEnglishOrTranslationAndKeepsOrder() throws {
        let session = CaptionSession(id: UUID(), createdAt: .now, captions: [
            Caption(id: UUID(), english: "Please send the minutes", chinese: "请把会议纪要发给团队", isProvisional: false, createdAt: .now),
            Caption(id: UUID(), english: "The next session starts at noon", chinese: "下一场中午开始", isProvisional: false, createdAt: .now)
        ])

        XCTAssertEqual(session.captions(matching: "  ").map(\.english), session.captions.map(\.english))
        XCTAssertEqual(session.captions(matching: "MINUTES").map(\.english), ["Please send the minutes"])
        XCTAssertEqual(session.captions(matching: "会议纪要").map(\.english), ["Please send the minutes"])
        XCTAssertTrue(session.captions(matching: "kubernetes").isEmpty)
    }

    func testTranscriptLinePutsEnglishAboveTranslation() {
        let translated = Caption(id: UUID(), english: "hello", chinese: "你好", isProvisional: false, createdAt: .now)
        let englishOnly = Caption(id: UUID(), english: "hello", chinese: nil, isProvisional: false, createdAt: .now)

        XCTAssertEqual(translated.transcriptLine, "hello\n你好")
        XCTAssertEqual(englishOnly.transcriptLine, "hello")
        XCTAssertEqual(CaptionSession(id: UUID(), createdAt: .now, captions: [translated, englishOnly]).transcriptText, "hello\n你好\n\nhello")
    }

    /// 识别错了要能改这一条，并且仍是原来那场，导出读到的是改正后的字。
    func testCorrectionStaysInTheSameSession() throws {
        let store = SessionStore(directory: directory)
        let caption = Caption(id: UUID(), english: "Looks rest are gone.", chinese: "看来其余的都走了。", isProvisional: false, createdAt: .now)
        let session = try store.save(captions: [caption])

        let corrected = try XCTUnwrap(session.updating(
            captionID: caption.id,
            english: "  The rooks rest are gone. ",
            chinese: "  "
        ))
        try store.update(corrected)

        let reloaded = try XCTUnwrap(try store.loadSessions().first)
        XCTAssertEqual(reloaded.id, session.id)
        XCTAssertEqual(try store.loadSessions().count, 1)
        XCTAssertEqual(reloaded.captions.map(\.english), ["The rooks rest are gone."])
        XCTAssertEqual(reloaded.captions.map(\.chinese), [nil])
        XCTAssertNil(session.updating(captionID: caption.id, english: "   ", chinese: "仍在"))
    }

    /// 一句被切成前后两行时，并进前一条；后面另一句还在，时间仍是前一条的。
    func testMergeWithNextJoinsTheSplitSentenceAndKeepsTheFollowingLine() {
        let firstTime = Date(timeIntervalSince1970: 1_700_000_000)
        let laterTime = Date(timeIntervalSince1970: 1_700_000_004)
        let first = Caption(id: UUID(), english: "capability.", chinese: "能力。", isProvisional: false, createdAt: firstTime)
        let second = Caption(id: UUID(), english: "Or your quickness of mind.", chinese: "或是你思维敏捷。", isProvisional: false, createdAt: laterTime)
        let third = Caption(id: UUID(), english: "There's been peace.", chinese: "一直和平。", isProvisional: false, createdAt: laterTime.addingTimeInterval(4))
        let session = CaptionSession(id: UUID(), createdAt: firstTime, captions: [first, second, third])

        let merged = session.mergingWithNext(captionID: first.id)

        XCTAssertEqual(merged?.captions.map(\.id), [first.id, third.id])
        XCTAssertEqual(merged?.captions.map(\.english), ["capability. Or your quickness of mind.", "There's been peace."])
        XCTAssertEqual(merged?.captions.map(\.chinese), ["能力。 或是你思维敏捷。", "一直和平。"])
        XCTAssertEqual(merged?.captions.first?.createdAt, firstTime)
        XCTAssertNil(session.mergingWithNext(captionID: third.id))
    }

    /// 连续相同的幻觉句收成第一条；隔着别的句子再说一次的要留下。
    func testCollapseKeepsOneCopyOfAConsecutiveRepeatAndALaterRepeat() {
        let you = Caption(id: UUID(), english: "you", chinese: "你", isProvisional: false, createdAt: .now)
        let youAgain = Caption(id: UUID(), english: " You ", chinese: "你啊", isProvisional: false, createdAt: .now)
        let other = Caption(id: UUID(), english: "There's been peace.", chinese: "一直和平。", isProvisional: false, createdAt: .now)
        let youLater = Caption(id: UUID(), english: "you", chinese: "你", isProvisional: false, createdAt: .now)
        let session = CaptionSession(id: UUID(), createdAt: .now, captions: [you, youAgain, other, youLater])

        XCTAssertTrue(session.hasConsecutiveDuplicateEnglish)
        let collapsed = session.collapsingConsecutiveDuplicates()
        XCTAssertEqual(collapsed.captions.map(\.id), [you.id, other.id, youLater.id])
        XCTAssertEqual(collapsed.captions.map(\.chinese), ["你", "一直和平。", "你"])
        XCTAssertFalse(collapsed.hasConsecutiveDuplicateEnglish)
    }

    /// 同一段视频听了几次，合成一场时按记录先后接上，不丢掉任何一次的句子，并删掉后来的记录文件。
    func testMergeSessionsKeepsEveryTakeInTimeOrderUnderTheEarliestSession() throws {
        let store = SessionStore(directory: directory)
        let earlierTime = Date(timeIntervalSince1970: 1_700_000_000)
        let laterTime = earlierTime.addingTimeInterval(600)
        let earlierCaption = Caption(id: UUID(), english: "Looks rest are gone.", chinese: "看来其余的都走了。", isProvisional: false, createdAt: earlierTime)
        let laterCaption = Caption(id: UUID(), english: "The rooks rest are gone.", chinese: "鸦巢已空。", isProvisional: false, createdAt: laterTime)
        let earlier = CaptionSession(id: UUID(), createdAt: earlierTime, captions: [earlierCaption])
        let later = CaptionSession(id: UUID(), createdAt: laterTime, captions: [laterCaption])

        XCTAssertNil(CaptionSession.merging([earlier]))
        let merged = try XCTUnwrap(CaptionSession.merging([later, earlier]))
        XCTAssertEqual(merged.id, earlier.id)
        XCTAssertEqual(merged.createdAt, earlierTime)
        XCTAssertEqual(merged.captions.map(\.english), ["Looks rest are gone.", "The rooks rest are gone."])

        try store.update(earlier)
        try store.update(later)
        try store.merge([later, earlier])

        let listed = try store.loadSessions()
        XCTAssertEqual(listed.map(\.id), [earlier.id])
        XCTAssertEqual(listed.first?.captions.map(\.english), ["Looks rest are gone.", "The rooks rest are gone."])
    }

    func testDeletedSessionIsNoLongerListed() throws {
        let store = SessionStore(directory: directory)
        let session = try store.save(captions: [])

        try store.delete(sessionID: session.id)

        XCTAssertTrue(try store.loadSessions().isEmpty)
    }
}
