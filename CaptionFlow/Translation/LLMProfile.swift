import Foundation

struct LLMProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var apiStyle: LLMAPIStyle
    var baseURL: URL
    var model: String

    init(id: UUID = UUID(), name: String, apiStyle: LLMAPIStyle, baseURL: URL, model: String) {
        self.id = id
        self.name = name
        self.apiStyle = apiStyle
        self.baseURL = baseURL
        self.model = model
    }
}
