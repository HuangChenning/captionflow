import Foundation

struct GlossaryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var source: String
    var target: String

    init(id: UUID = UUID(), source: String, target: String) { self.id = id; self.source = source; self.target = target }

    /// 人名、产品名这类专有名词：至少一个词是首字母大写且含小写字母（"Lucas"、"Kubernetes"）。
    /// 全小写术语（"minutes"）和全大写缩写（"API"）不算，避免把普通词条都当成可能听错的名字。
    var isProperNoun: Bool {
        source.split { !$0.isLetter }.contains { word in
            guard let first = word.first, first.isUppercase else { return false }
            return word.dropFirst().contains(where: \.isLowercase)
        }
    }
}
