import Foundation

struct Caption: Identifiable, Codable, Equatable {
    /// LLM 精修的进度；nil 表示这条字幕没有经过精修（仅本地、仅 LLM 或只显示英文）。
    enum Refinement: String, Codable {
        case refining, refined, failed
    }

    let id: UUID
    var english: String
    var chinese: String?
    var isProvisional: Bool
    let createdAt: Date
    // 可选且有默认值：没有这个字段的旧历史记录仍能解码。
    var refinement: Refinement? = nil

    func replacing(english: String, chinese: String?) -> Self {
        Self(
            id: id,
            english: english,
            chinese: chinese,
            isProvisional: true,
            createdAt: createdAt
        )
    }
}
