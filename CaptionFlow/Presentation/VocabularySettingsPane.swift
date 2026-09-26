import SwiftUI

struct VocabularySettingsPane: View {
    @State private var entries: [GlossaryEntry] = []
    @State private var candidates: [TermCandidate] = []
    @State private var ignoredTerms: [String] = []
    @State private var candidateSource = ""
    @State private var candidateTarget = ""
    @State private var errorMessage: String?
    private let store = GlossaryStore()
    private let candidateStore = TermCandidateStore()
    private let ignoredStore = IgnoredTermStore()

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
                Text("已确认的词汇会在 LLM 翻译时使用，仅本地翻译模式下不生效。修改在下次开始字幕时生效。")
            }
            Section {
                if candidates.isEmpty {
                    Text("没有待确认的候选。可在“字幕历史”中右键某次会话，选择“提取术语候选”。")
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
                Text("候选由 LLM 从字幕历史中提出，只有点“采纳”后才会加入已确认词库。忽略过的术语之后不会再作为候选出现，可在下方“已忽略”中恢复。")
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
