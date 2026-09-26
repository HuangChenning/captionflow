import Foundation

struct GlossaryStore {
    let fileURL: URL

    init(fileURL: URL = GlossaryStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> [GlossaryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([GlossaryEntry].self, from: Data(contentsOf: fileURL))
    }

    func save(_ entries: [GlossaryEntry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("CaptionFlow/glossary.json")
    }
}
