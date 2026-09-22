import Foundation

enum LLMAPIStyle: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAICompatible: return "OpenAI-compatible"
        }
    }
}
