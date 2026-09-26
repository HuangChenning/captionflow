import SwiftUI

struct VocabularySettingsPane: View {
    @State private var entries: [GlossaryEntry] = []
    @State private var candidateSource = ""
    @State private var candidateTarget = ""
    @State private var errorMessage: String?
    private let store = GlossaryStore()

    private var trimmedSource: String { candidateSource.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTarget: String { candidateTarget.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool {
        entries.contains { $0.source.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmedSource) == .orderedSame }
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
        .alert("无法保存词库", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func load() {
        do { entries = try store.load() }
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
