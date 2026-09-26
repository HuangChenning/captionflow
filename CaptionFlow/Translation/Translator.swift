import Foundation

protocol Translator: Sendable {
    func translate(_ text: String) async throws -> String
}

/// 拿到英文原文和本地初译（可能没有），返回修正后的译文。
protocol CaptionRefiner: Sendable {
    func refine(english: String, localDraft: String?) async throws -> String
}
