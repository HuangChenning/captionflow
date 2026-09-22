import Foundation

struct Caption: Identifiable, Codable, Equatable {
    let id: UUID
    var english: String
    var chinese: String?
    var isProvisional: Bool
    let createdAt: Date

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
