import XCTest
@testable import CaptionFlow

final class KeychainStoreTests: XCTestCase {
    func testSecretCanBeReadThenDeleted() throws {
        let store = KeychainStore(service: "com.taihongteng.CaptionFlow.tests")
        try store.save(secret: "test-key", for: "openai")
        XCTAssertEqual(try store.secret(for: "openai"), "test-key")
        try store.deleteSecret(for: "openai")
        XCTAssertNil(try store.secret(for: "openai"))
    }

    func testConfigurationRejectsInsecureEndpointAndEmptyModel() {
        XCTAssertNotNil(LLMConfiguration(baseURL: URL(string: "https://api.example.com/v1")!, model: "model", instruction: "translate"))
        XCTAssertNil(LLMConfiguration(baseURL: URL(string: "ftp://example.com")!, model: "model", instruction: "translate"))
        XCTAssertNil(LLMConfiguration(baseURL: URL(string: "https://api.example.com")!, model: " ", instruction: "translate"))
    }

    func testProfileFileStoreRoundTripsProfilesAsJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("profiles.json")
        let profile = LLMProfile(name: "MiniMax", apiStyle: .anthropic, baseURL: URL(string: "https://api.minimaxi.com/anthropic")!, model: "MiniMax-M3")

        try LLMProfileFileStore(fileURL: fileURL).save([profile])

        XCTAssertEqual(try LLMProfileFileStore(fileURL: fileURL).load(), [profile])
        XCTAssertTrue(String(decoding: try Data(contentsOf: fileURL), as: UTF8.self).contains("MiniMax-M3"))
    }

    func testGlossaryStorePersistsConfirmedTerms() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GlossaryStore(fileURL: directory.appendingPathComponent("glossary.json"))
        let entry = GlossaryEntry(source: "minutes", target: "会议纪要")

        try store.save([entry])

        XCTAssertEqual(try store.load(), [entry])
    }
}
