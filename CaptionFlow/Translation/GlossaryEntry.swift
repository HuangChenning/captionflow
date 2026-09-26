import Foundation

struct GlossaryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var source: String
    var target: String

    init(id: UUID = UUID(), source: String, target: String) { self.id = id; self.source = source; self.target = target }
}
