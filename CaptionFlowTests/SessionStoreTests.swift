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

    func testDeletedSessionIsNoLongerListed() throws {
        let store = SessionStore(directory: directory)
        let session = try store.save(captions: [])

        try store.delete(sessionID: session.id)

        XCTAssertTrue(try store.loadSessions().isEmpty)
    }
}
