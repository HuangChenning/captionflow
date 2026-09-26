import Foundation

/// LLM 从某次会话中提出的术语候选。只有用户采纳后才会写入已确认词库（GlossaryStore）。
struct TermCandidate: Codable, Equatable, Identifiable {
    /// “自定义词汇”里“从字幕历史分析”每次只看最近这么多场，避免一次请求过多。
    static let recentAnalysisSessionLimit = 5

    let id: UUID
    var source: String
    var target: String
    /// 会话里包含该术语的英文原句，供用户判断候选是否合理。
    let example: String
    /// 候选来自哪一次会话（会话开始时间）。多场分析时取最近一场包含该术语的会话。
    let sessionDate: Date
    /// 代码在所分析字幕里统计的出现次数。旧的候选文件没有这个字段，解码为 nil。
    var occurrences: Int?

    init(id: UUID = UUID(), source: String, target: String, example: String, sessionDate: Date, occurrences: Int? = nil) {
        self.id = id
        self.source = source
        self.target = target
        self.example = example
        self.sessionDate = sessionDate
        self.occurrences = occurrences
    }

    /// 用户在“添加新词汇”里输入的词。先进入待确认，不写进已确认词库。没有例句，因此不是从会话提取的。
    /// 英文为空，或与已有词库、候选、忽略列表重复时，不添加。译文可以先空着，之后再改或优化。
    static func addedByUser(source: String, target: String, existingSources: [String]) -> TermCandidate? {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        guard !existingSources.contains(where: { $0.caseInsensitiveCompare(source) == .orderedSame }) else { return nil }
        return TermCandidate(source: source, target: target, example: "", sessionDate: .now, occurrences: nil)
    }

    var isManual: Bool {
        example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 把 LLM 的提议整理成候选。示例句和出现次数都由代码从会话原文统计，不采用 LLM 的说法：
    /// 在原文中找不到的术语视为 LLM 编造而丢弃；已在词库、已在候选列表或重复的术语也丢弃。
    static func make(
        from proposals: [GlossaryEntry],
        session: CaptionSession,
        excluding existingSources: [String]
    ) -> [TermCandidate] {
        make(from: proposals, sessions: [session], excluding: existingSources)
    }

    static func make(
        from proposals: [GlossaryEntry],
        sessions: [CaptionSession],
        excluding existingSources: [String]
    ) -> [TermCandidate] {
        let captions = sessions.flatMap(\.captions)
        var seen = Set(existingSources.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return proposals.compactMap { proposal in
            let source = proposal.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = proposal.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !target.isEmpty, seen.insert(source.lowercased()).inserted else { return nil }
            guard let match = sessions.lazy.compactMap({ session -> (Date, String)? in
                guard let example = session.captions.first(where: { $0.english.range(of: source, options: .caseInsensitive) != nil })?.english else {
                    return nil
                }
                return (session.createdAt, example)
            }).first else { return nil }
            return TermCandidate(
                source: source,
                target: target,
                example: match.1,
                sessionDate: match.0,
                occurrences: occurrenceCount(of: source, in: captions)
            )
        }
    }

    /// 在字幕原文中数短语出现了几次，大小写不敏感、不重叠。次数必须来自原文，不能信 LLM。
    static func occurrenceCount(of phrase: String, in captions: [Caption]) -> Int {
        let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return 0 }
        return captions.reduce(0) { total, caption in
            var count = 0
            var start = caption.english.startIndex
            while let range = caption.english.range(of: needle, options: .caseInsensitive, range: start..<caption.english.endIndex) {
                count += 1
                start = range.upperBound
            }
            return total + count
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
        try record(proposals, from: [session], candidateStore: candidateStore, glossaryStore: glossaryStore, ignoredStore: ignoredStore)
    }

    /// 多场会话一起统计出现次数。传入顺序应为最近的在前，示例句和来源日期取最近一场包含该术语的会话。
    static func record(
        _ proposals: [GlossaryEntry],
        from sessions: [CaptionSession],
        candidateStore: TermCandidateStore = TermCandidateStore(),
        glossaryStore: GlossaryStore = GlossaryStore(),
        ignoredStore: IgnoredTermStore = IgnoredTermStore()
    ) throws -> [TermCandidate] {
        let pending = try candidateStore.load()
        let existing = try glossaryStore.load().map(\.source) + pending.map(\.source) + ignoredStore.load()
        let found = make(from: proposals, sessions: sessions, excluding: existing)
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
