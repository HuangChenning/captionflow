import Foundation

protocol Translator: Sendable {
    func translate(_ text: String) async throws -> String
}
