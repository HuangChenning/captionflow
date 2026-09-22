import Foundation

enum TranslationEngineMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case localOnly
    case llmOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动（LLM 优先，失败时使用本地翻译）"
        case .localOnly: return "仅使用本地翻译"
        case .llmOnly: return "仅使用 LLM 翻译"
        }
    }
}
