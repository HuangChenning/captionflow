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
}
