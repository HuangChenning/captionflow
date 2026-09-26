import Foundation

struct CaptionSession: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let captions: [Caption]
}

struct SessionStore {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL = SessionStore.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func save(captions: [Caption]) throws -> CaptionSession {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = CaptionSession(id: UUID(), createdAt: .now, captions: captions)
        let data = try JSONEncoder().encode(session)
        try data.write(to: fileURL(for: session.id), options: .atomic)
        return session
    }

    func loadSessions() throws -> [CaptionSession] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(CaptionSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func delete(sessionID: UUID) throws {
        let url = fileURL(for: sessionID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func exportText(sessionID: UUID, to destinationURL: URL) throws {
        guard let session = try loadSessions().first(where: { $0.id == sessionID }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let formatter = ISO8601DateFormatter()
        let lines = session.captions.map { caption in
            let chinese = caption.chinese.map { "\n\($0)" } ?? ""
            return "[\(formatter.string(from: caption.createdAt))]\n\(caption.english)\(chinese)"
        }
        try lines.joined(separator: "\n\n").write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    private func fileURL(for sessionID: UUID) -> URL {
        directory.appendingPathComponent(sessionID.uuidString).appendingPathExtension("json")
    }

    private static var defaultDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("CaptionFlow/Sessions", isDirectory: true)
    }
}
