import SwiftUI

struct VocabularySettingsPane: View {
    @State private var entries: [GlossaryEntry] = []
    @State private var candidates: [TermCandidate] = []
    @State private var ignoredTerms: [String] = []
    @State private var candidateSource = ""
    @State private var candidateTarget = ""
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var analysisMessage: String?
    private let store = GlossaryStore()
    private let candidateStore = TermCandidateStore()
    private let ignoredStore = IgnoredTermStore()
    private let sessionStore = SessionStore()

    private var trimmedSource: String { candidateSource.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTarget: String { candidateTarget.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool { isInGlossary(trimmedSource) }

    private func isInGlossary(_ source: String) -> Bool {
        entries.contains { $0.source.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(source) == .orderedSame }
    }

    var body: some View {
        Form {
            Section {
                TextField("英文术语", text: $candidateSource)
                TextField("简体中文", text: $candidateTarget)
                Button("添加到已确认词库") { confirmCandidate() }
                    .disabled(trimmedSource.isEmpty || trimmedTarget.isEmpty || isDuplicate)
                if isDuplicate {
                    Text("“\(trimmedSource)”已在词库中，可在下方直接修改。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("添加新词汇")
            } footer: {
                Text("已确认的词汇会在 LLM 翻译时使用，仅本地翻译模式下不生效。修改在下次开始字幕时生效。其中首字母大写的人名和产品名还会在精修时作为可能听错的名字提供给模型，原文里没有原样出现时也能用来还原识别错误。")
            }
            Section {
                Button(isAnalyzing ? "正在分析字幕历史…" : "从字幕历史分析") {
                    Task { await analyzeRecentSessions() }
                }
                .disabled(isAnalyzing)
                if candidates.isEmpty && !isAnalyzing {
                    Text("没有待确认的候选。")
                        .foregroundStyle(.secondary)
                }
                ForEach($candidates) { $candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(candidate.source)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField("译文", text: $candidate.target)
                            Button("采纳") { accept(candidate) }
                                .disabled(isInGlossary(candidate.source)
                                    || candidate.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("忽略") { ignore(candidate) }
                        }
                        .buttonStyle(.borderless)
                        Group {
                            Text("来源：\(candidate.sessionDate.formatted(date: .abbreviated, time: .shortened)) 的会话")
                            if let occurrences = candidate.occurrences {
                                Text("出现 \(occurrences) 次")
                            }
                            Text("示例：\(candidate.example)").lineLimit(2)
                            if isInGlossary(candidate.source) {
                                Text("已在词库中，可以忽略。")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("待确认候选")
            } footer: {
                Text("“从字幕历史分析”让 LLM 从最近 \(TermCandidate.recentAnalysisSessionLimit) 场会话里提出术语和反复出现的短语，出现次数由程序在字幕原文中统计。只有点“采纳”后才会加入已确认词库。也可以在“字幕历史”里对单场会话右键提取。忽略过的术语之后不会再作为候选出现，可在下方“已忽略”中恢复。")
            }
            if !ignoredTerms.isEmpty {
                Section {
                    ForEach(ignoredTerms, id: \.self) { term in
                        HStack {
                            Text(term)
                            Spacer()
                            Button("恢复") { restore(term) }
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("已忽略")
                } footer: {
                    Text("恢复后，下次提取术语候选时这个词可以再次出现。")
                }
            }
            Section("已确认词库") {
                if entries.isEmpty {
                    Text("还没有词汇").foregroundStyle(.secondary)
                }
                ForEach($entries) { $entry in
                    HStack {
                        TextField("英文", text: $entry.source)
                        TextField("中文", text: $entry.target)
                        Button {
                            entries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("自定义词汇")
        .onAppear(perform: load)
        .onChange(of: entries) { save() }
        .onChange(of: candidates) { saveCandidates() }
        .alert("无法保存词库", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .alert("术语候选", isPresented: Binding(get: { analysisMessage != nil }, set: { if !$0 { analysisMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(analysisMessage ?? "") }
    }

    /// 分析最近几场字幕历史，新候选进入待确认列表，不写入已确认词库。
    private func analyzeRecentSessions() async {
        let target = UserDefaults.standard.string(forKey: "translation.targetLanguage")
            .flatMap(TargetLanguage.init(rawValue:)) ?? .simplifiedChinese
        guard let translator = CaptionSessionController.makeLLMTranslator(targetLanguage: target) else {
            errorMessage = "还没有可用的 LLM 配置，请先在“模型”中选择配置并填写 API Key。"
            return
        }
        let sessions: [CaptionSession]
        do {
            sessions = try sessionStore.loadSessions()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let recent = Array(sessions.prefix(TermCandidate.recentAnalysisSessionLimit))
        guard recent.contains(where: { !$0.captions.isEmpty }) else {
            analysisMessage = recent.isEmpty ? "还没有字幕历史。开始一次字幕后再分析。" : "最近的会话里没有字幕。"
            return
        }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let proposals = try await translator.proposeTerms(for: recent.flatMap(\.captions))
            let found = try TermCandidate.record(proposals, from: recent)
            candidates = try candidateStore.load()
            analysisMessage = found.isEmpty
                ? "没有找到新的术语候选。"
                : "从最近 \(recent.count) 场会话中找到 \(found.count) 个候选，请逐条确认。"
        } catch LLMTranslatorError.malformedTermList {
            errorMessage = "LLM 返回的内容不是有效的术语列表，可以再试一次。"
        } catch {
            errorMessage = "分析字幕历史失败：\(error.localizedDescription)"
        }
    }

    private func load() {
        do {
            entries = try store.load()
            candidates = try candidateStore.load()
            ignoredTerms = try ignoredStore.load()
        } catch { errorMessage = error.localizedDescription }
    }

    private func accept(_ candidate: TermCandidate) {
        entries.append(GlossaryEntry(
            source: candidate.source,
            target: candidate.target.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        candidates.removeAll { $0.id == candidate.id }
    }

    private func ignore(_ candidate: TermCandidate) {
        do {
            try ignoredStore.add(candidate.source)
            ignoredTerms = try ignoredStore.load()
            candidates.removeAll { $0.id == candidate.id }
        } catch { errorMessage = error.localizedDescription }
    }

    private func restore(_ term: String) {
        do {
            try ignoredStore.remove(term)
            ignoredTerms = try ignoredStore.load()
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveCandidates() {
        do { try candidateStore.save(candidates) }
        catch { errorMessage = error.localizedDescription }
    }

    private func confirmCandidate() {
        entries.append(GlossaryEntry(source: trimmedSource, target: trimmedTarget))
        candidateSource = ""
        candidateTarget = ""
    }

    private func save() {
        do { try store.save(entries) }
        catch { errorMessage = error.localizedDescription }
    }
}
