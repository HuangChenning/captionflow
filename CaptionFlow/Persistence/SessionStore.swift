import Foundation

struct CaptionSession: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let captions: [Caption]

    /// 空查询返回全部字幕。按英文或译文匹配，忽略大小写。
    func captions(matching query: String) -> [Caption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return captions }
        return captions.filter { caption in
            caption.english.localizedStandardContains(trimmed)
                || caption.chinese?.localizedStandardContains(trimmed) == true
        }
    }

    var transcriptText: String {
        captions.map(\.transcriptLine).joined(separator: "\n\n")
    }

    /// 改正识别或译文。英文清空时不改，避免把一条字幕擦掉。
    func updating(captionID: UUID, english: String, chinese: String?) -> CaptionSession? {
        let trimmedEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEnglish.isEmpty,
              let index = captions.firstIndex(where: { $0.id == captionID }) else { return nil }
        var updated = captions
        updated[index].english = trimmedEnglish
        let trimmedChinese = chinese?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updated[index].chinese = trimmedChinese.isEmpty ? nil : trimmedChinese
        return replacingCaptions(updated)
    }

    /// 一句被停顿切成两行时，并进前一条，保留前一条的时间和后续句子。
    func mergingWithNext(captionID: UUID) -> CaptionSession? {
        guard let index = captions.firstIndex(where: { $0.id == captionID }),
              index + 1 < captions.count else { return nil }
        var merged = captions[index]
        let next = captions[index + 1]
        merged.english = joinCaptionText(merged.english, next.english)
        merged.chinese = joinOptionalCaptionText(merged.chinese, next.chinese)
        var updated = captions
        updated[index] = merged
        updated.remove(at: index + 1)
        return replacingCaptions(updated)
    }

    /// 只收紧挨着、英文相同的字幕（如连续的 “you”）。隔开的同一句会留下。保留第一条的译文。
    func collapsingConsecutiveDuplicates() -> CaptionSession {
        var kept: [Caption] = []
        for caption in captions {
            if let previous = kept.last, sameSpokenEnglish(previous.english, caption.english) {
                continue
            }
            kept.append(caption)
        }
        return replacingCaptions(kept)
    }

    var hasConsecutiveDuplicateEnglish: Bool {
        zip(captions, captions.dropFirst()).contains { sameSpokenEnglish($0.english, $1.english) }
    }

    private func replacingCaptions(_ captions: [Caption]) -> CaptionSession {
        CaptionSession(id: id, createdAt: createdAt, captions: captions)
    }

    /// 同一段视频的多场记录合成一场：按记录时间先后接上，每场内部的句子顺序不动。留下最早那场的身份。不足两场时不合并。
    static func merging(_ sessions: [CaptionSession]) -> CaptionSession? {
        let ordered = sessions.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard ordered.count >= 2, let earliest = ordered.first else { return nil }
        return CaptionSession(id: earliest.id, createdAt: earliest.createdAt, captions: ordered.flatMap(\.captions))
    }
}

private func sameSpokenEnglish(_ lhs: String, _ rhs: String) -> Bool {
    let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
    let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
    return !left.isEmpty && left.localizedCaseInsensitiveCompare(right) == .orderedSame
}

private func joinCaptionText(_ lhs: String, _ rhs: String) -> String {
    let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
    let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
    if left.isEmpty { return right }
    if right.isEmpty { return left }
    return "\(left) \(right)"
}

private func joinOptionalCaptionText(_ lhs: String?, _ rhs: String?) -> String? {
    let joined = joinCaptionText(lhs ?? "", rhs ?? "")
    return joined.isEmpty ? nil : joined
}

extension Caption {
    /// 复制或展示用的一行：有译文时英文在上、译文在下。
    var transcriptLine: String {
        guard let chinese, !chinese.isEmpty else { return english }
        return "\(english)\n\(chinese)"
    }
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

    func update(_ session: CaptionSession) throws {
        let data = try JSONEncoder().encode(session)
        try data.write(to: fileURL(for: session.id), options: .atomic)
    }

    /// 写成最早那场，再删掉其余记录。各次识别的句子都保留。
    func merge(_ sessions: [CaptionSession]) throws {
        guard let merged = CaptionSession.merging(sessions) else { return }
        try update(merged)
        for session in sessions where session.id != merged.id {
            try delete(sessionID: session.id)
        }
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
