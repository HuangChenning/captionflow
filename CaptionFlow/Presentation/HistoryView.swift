import AppKit
import SwiftUI

struct HistoryView: View {
    @State private var sessions: [CaptionSession] = []
    @State private var errorMessage: String?
    @State private var extractingSessionID: UUID?
    @State private var resultMessage: String?
    private let store = SessionStore()

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("还没有字幕历史。")
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.createdAt, format: .dateTime)
                    Text(extractingSessionID == session.id ? "正在提取术语候选…" : "\(session.captions.count) 条字幕")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("导出文本…") { export(session) }
                    Button("提取术语候选") { Task { await extractTerms(from: session) } }
                        .disabled(extractingSessionID != nil)
                    Button("删除", role: .destructive) { delete(session) }
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("字幕历史")
        .toolbar { Button("刷新", action: load) }
        .alert("无法处理字幕历史", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: {
            Text(errorMessage ?? "")
        }
        .alert("术语候选", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: {
            Text(resultMessage ?? "")
        }
        .onAppear(perform: load)
    }

    private func load() {
        do { sessions = try store.loadSessions() }
        catch { errorMessage = error.localizedDescription }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { delete(sessions[index]) }
    }

    private func delete(_ session: CaptionSession) {
        do { try store.delete(sessionID: session.id); load() }
        catch { errorMessage = error.localizedDescription }
    }

    /// 候选只写入待确认列表，由用户在“自定义词汇”中逐条采纳或忽略。
    private func extractTerms(from session: CaptionSession) async {
        let target = UserDefaults.standard.string(forKey: "translation.targetLanguage")
            .flatMap(TargetLanguage.init(rawValue:)) ?? .simplifiedChinese
        guard let translator = CaptionSessionController.makeLLMTranslator(targetLanguage: target) else {
            errorMessage = "还没有可用的 LLM 配置，请先在“模型”中选择配置并填写 API Key。"
            return
        }
        extractingSessionID = session.id
        defer { extractingSessionID = nil }
        do {
            let proposals = try await translator.proposeTerms(for: session.captions)
            // 等待 LLM 期间用户可能改过词库或候选，回复到达后再读取。
            let candidateStore = TermCandidateStore()
            let pending = try candidateStore.load()
            let glossary = try GlossaryStore().load()
            let found = TermCandidate.make(
                from: proposals,
                session: session,
                excluding: glossary.map(\.source) + pending.map(\.source)
            )
            try candidateStore.save(pending + found)
            resultMessage = found.isEmpty
                ? "没有找到新的术语候选。"
                : "找到 \(found.count) 个术语候选，请到“自定义词汇”中逐条确认。"
        } catch LLMTranslatorError.malformedTermList {
            errorMessage = "LLM 返回的内容不是有效的术语列表，可以再试一次。"
        } catch {
            errorMessage = "提取术语候选失败：\(error.localizedDescription)"
        }
    }

    private func export(_ session: CaptionSession) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CaptionFlow-\(session.id.uuidString).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportText(sessionID: session.id, to: url) }
        catch { errorMessage = error.localizedDescription }
    }
}
