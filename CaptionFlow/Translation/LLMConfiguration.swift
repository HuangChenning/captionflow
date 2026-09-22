import Foundation

struct LLMConfiguration: Codable, Equatable {
    let baseURL: URL
    let model: String
    let instruction: String

    init?(baseURL: URL, model: String, instruction: String) {
        guard baseURL.scheme?.lowercased() == "https",
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.baseURL = baseURL
        self.model = model
        self.instruction = instruction
    }
}
