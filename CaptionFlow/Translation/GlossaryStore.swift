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

    /// 去掉首尾空白，丢弃英文或中文为空的词条，避免把编辑到一半的空行写进词库。
    func save(_ entries: [GlossaryEntry]) throws {
        let entries = entries.compactMap { entry -> GlossaryEntry? in
            let source = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !target.isEmpty else { return nil }
            return GlossaryEntry(id: entry.id, source: source, target: target)
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("CaptionFlow/glossary.json")
    }
}
