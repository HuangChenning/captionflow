import SwiftUI

struct VocabularySettingsPane: View {
    @State private var entries: [GlossaryEntry] = []
    @State private var candidateSource = ""
    @State private var candidateTarget = ""
    @State private var errorMessage: String?
    private let store = GlossaryStore()

    var body: some View {
        Form {
            Section {
                TextField("英文术语", text: $candidateSource)
                TextField("简体中文", text: $candidateTarget)
                Button("添加到已确认词库") { confirmCandidate() }
                    .disabled(candidateSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || candidateTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("添加新词汇")
            } footer: {
                Text("输入英文和对应简体中文后即可添加。LLM 候选也必须经你确认才会进入后续翻译使用的词库。")
            }
            Section("已确认词库") {
                ForEach($entries) { $entry in
                    HStack {
                        TextField("英文", text: $entry.source)
                        TextField("中文", text: $entry.target)
                    }
                }
                .onDelete { offsets in entries.remove(atOffsets: offsets); save() }
                Button("保存修改", action: save)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("自定义词汇")
        .onAppear(perform: load)
        .alert("无法保存词库", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func load() {
        do { entries = try store.load() }
        catch { errorMessage = error.localizedDescription }
    }

    private func confirmCandidate() {
        entries.append(GlossaryEntry(source: candidateSource.trimmingCharacters(in: .whitespacesAndNewlines), target: candidateTarget.trimmingCharacters(in: .whitespacesAndNewlines)))
        candidateSource = ""
        candidateTarget = ""
        save()
    }

    private func save() {
        do { try store.save(entries) }
        catch { errorMessage = error.localizedDescription }
    }
}
