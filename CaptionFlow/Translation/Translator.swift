import Foundation

protocol Translator: Sendable {
    func translate(_ text: String) async throws -> String
}

/// 拿到英文原文和本地初译（可能没有），返回修正后的译文。
/// previousEnglish 是上一条字幕的英文：断句常在句中停顿处切开，后半句单独翻译会缺上下文。
protocol CaptionRefiner: Sendable {
    func refine(english: String, localDraft: String?, previousEnglish: String?) async throws -> String
}
