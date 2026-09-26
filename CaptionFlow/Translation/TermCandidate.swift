import Foundation

/// LLM 从某次会话中提出的术语候选。只有用户采纳后才会写入已确认词库（GlossaryStore）。
struct TermCandidate: Codable, Equatable, Identifiable {
    let id: UUID
    var source: String
    var target: String
    /// 会话里包含该术语的英文原句，供用户判断候选是否合理。
    let example: String
    /// 候选来自哪一次会话（会话开始时间）。
    let sessionDate: Date

    init(id: UUID = UUID(), source: String, target: String, example: String, sessionDate: Date) {
        self.id = id
        self.source = source
        self.target = target
        self.example = example
        self.sessionDate = sessionDate
    }

    /// 把 LLM 的提议整理成候选。示例句由代码从会话原文中查找，不采用 LLM 的说法：
    /// 在原文中找不到的术语视为 LLM 编造而丢弃；已在词库、已在候选列表或重复的术语也丢弃。
    static func make(
        from proposals: [GlossaryEntry],
        session: CaptionSession,
        excluding existingSources: [String]
    ) -> [TermCandidate] {
        var seen = Set(existingSources.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return proposals.compactMap { proposal in
            let source = proposal.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = proposal.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !target.isEmpty, seen.insert(source.lowercased()).inserted,
                  let example = session.captions.first(where: { $0.english.range(of: source, options: .caseInsensitive) != nil })?.english
            else { return nil }
            return TermCandidate(source: source, target: target, example: example, sessionDate: session.createdAt)
        }
    }

    /// 把一次提取的结果加入待确认列表并返回新增的候选。
    /// 已在词库、已在候选列表或用户忽略过的术语不再提出。
    static func record(
        _ proposals: [GlossaryEntry],
        from session: CaptionSession,
        candidateStore: TermCandidateStore = TermCandidateStore(),
        glossaryStore: GlossaryStore = GlossaryStore(),
        ignoredStore: IgnoredTermStore = IgnoredTermStore()
    ) throws -> [TermCandidate] {
        let pending = try candidateStore.load()
        let existing = try glossaryStore.load().map(\.source) + pending.map(\.source) + ignoredStore.load()
        let found = make(from: proposals, session: session, excluding: existing)
        try candidateStore.save(pending + found)
        return found
    }
}

/// 待确认候选单独存放，与已确认词库分开，保证候选不会被当作已确认术语用于翻译。
struct TermCandidateStore {
    let fileURL: URL

    init(fileURL: URL = TermCandidateStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> [TermCandidate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([TermCandidate].self, from: Data(contentsOf: fileURL))
    }

    func save(_ candidates: [TermCandidate]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(candidates).write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("CaptionFlow/term-candidates.json")
    }
}

/// 用户点过“忽略”的英文术语，之后提取候选时不再提出。
struct IgnoredTermStore {
    let fileURL: URL

    init(fileURL: URL = IgnoredTermStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: fileURL))
    }

    func add(_ source: String) throws {
        let ignored = try load()
        guard !ignored.contains(where: { $0.caseInsensitiveCompare(source) == .orderedSame }) else { return }
        try save(ignored + [source])
    }

    /// 恢复后该术语在之后的提取中可以再次作为候选出现。
    func remove(_ source: String) throws {
        try save(load().filter { $0 != source })
    }

    private func save(_ ignored: [String]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ignored).write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("CaptionFlow/ignored-terms.json")
    }
}
