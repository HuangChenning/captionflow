import AppKit
import SwiftUI

struct HistoryView: View {
    @State private var sessions: [CaptionSession] = []
    @State private var errorMessage: String?
    @State private var extractingSessionID: UUID?
    @State private var resultMessage: String?
    @State private var sessionPendingDelete: CaptionSession?
    @State private var sessionsToMerge: Set<UUID> = []
    @State private var confirmMerge = false
    private let store = SessionStore()

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("还没有字幕历史。")
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(
                            session: session,
                            onExport: { export(session) },
                            onExtract: { await extractTerms(from: session) },
                            onDelete: { delete(session) },
                            onSave: { try save($0) }
                        )
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            selectionButton(for: session)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.createdAt, format: .dateTime)
                                Text(extractingSessionID == session.id ? "正在提取术语候选…" : "\(session.captions.count) 条字幕")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            rowButton("导出文本", systemImage: "square.and.arrow.up") {
                                export(session)
                            }
                            rowButton("删除", systemImage: "trash") {
                                sessionPendingDelete = session
                            }
                        }
                    }
                    .contextMenu {
                        Button("导出文本…") { export(session) }
                        Button("提取术语候选") {
                            Task { resultMessage = await extractTerms(from: session) }
                        }
                            .disabled(extractingSessionID != nil)
                        Button("删除", role: .destructive) { sessionPendingDelete = session }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("字幕历史")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        confirmMerge = true
                    } label: {
                        Image(systemName: "arrow.triangle.merge")
                    }
                    .disabled(sessionsToMerge.count < 2)
                    .help(sessionsToMerge.count < 2 ? "选择两场或更多字幕后合并" : "合并所选记录")
                    .accessibilityLabel("合并所选记录")
                    Button(action: load) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新")
                    .accessibilityLabel("刷新")
                }
            }
            .confirmationDialog("把所选字幕合成一场？", isPresented: $confirmMerge, titleVisibility: .visible) {
                Button("合并") { mergeSelected() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("按时间先后接成一场。各次识别的句子都会留下，其余记录会删除。")
            }
            .confirmationDialog(
                "删除这场字幕？",
                isPresented: Binding(
                    get: { sessionPendingDelete != nil },
                    set: { if !$0 { sessionPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: sessionPendingDelete
            ) { session in
                Button("删除", role: .destructive) { delete(session) }
                Button("取消", role: .cancel) {}
            } message: { session in
                Text("\(session.createdAt.formatted(date: .abbreviated, time: .shortened))，删除后无法恢复。")
            }
        }
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

    private func rowButton(_ help: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    private func selectionButton(for session: CaptionSession) -> some View {
        let selected = sessionsToMerge.contains(session.id)
        return Button {
            if selected {
                sessionsToMerge.remove(session.id)
            } else {
                sessionsToMerge.insert(session.id)
            }
        } label: {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .help(selected ? "取消选择" : "选择以合并")
        .accessibilityLabel(selected ? "取消选择" : "选择以合并")
    }

    private func load() {
        do {
            sessions = try store.loadSessions()
            sessionsToMerge.formIntersection(Set(sessions.map(\.id)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergeSelected() {
        let chosen = sessions.filter { sessionsToMerge.contains($0.id) }
        do {
            try store.merge(chosen)
            sessionsToMerge.removeAll()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { delete(sessions[index]) }
    }

    private func delete(_ session: CaptionSession) {
        do { try store.delete(sessionID: session.id); load() }
        catch { errorMessage = error.localizedDescription }
    }

    private func save(_ session: CaptionSession) throws {
        try store.update(session)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    /// 候选只写入待确认列表，由用户在“自定义词汇”中逐条采纳或忽略。返回要告诉用户的结果。
    private func extractTerms(from session: CaptionSession) async -> String {
        let target = UserDefaults.standard.string(forKey: "translation.targetLanguage")
            .flatMap(TargetLanguage.init(rawValue:)) ?? .simplifiedChinese
        guard let translator = CaptionSessionController.makeLLMTranslator(targetLanguage: target) else {
            return "还没有可用的 LLM 配置，请先在“模型”中选择配置并填写 API Key。"
        }
        extractingSessionID = session.id
        defer { extractingSessionID = nil }
        do {
            let proposals = try await translator.proposeTerms(for: session.captions)
            // 等待 LLM 期间用户可能改过词库或候选，回复到达后再读取。
            let found = try TermCandidate.record(proposals, from: session)
            return found.isEmpty
                ? "没有找到新的术语候选。"
                : "找到 \(found.count) 个术语候选，请到“自定义词汇”中逐条确认。"
        } catch LLMTranslatorError.malformedTermList {
            return "LLM 返回的内容不是有效的术语列表，可以再试一次。"
        } catch {
            return "提取术语候选失败：\(error.localizedDescription)"
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

private struct SessionDetailView: View {
    @State private var session: CaptionSession
    let onExport: () -> Void
    let onExtract: () async -> String
    let onDelete: () -> Void
    let onSave: (CaptionSession) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var extracting = false
    @State private var extractResult: String?
    @State private var editingCaption: Caption?
    @State private var saveError: String?
    @State private var confirmCollapse = false

    init(
        session: CaptionSession,
        onExport: @escaping () -> Void,
        onExtract: @escaping () async -> String,
        onDelete: @escaping () -> Void,
        onSave: @escaping (CaptionSession) throws -> Void
    ) {
        _session = State(initialValue: session)
        self.onExport = onExport
        self.onExtract = onExtract
        self.onDelete = onDelete
        self.onSave = onSave
    }

    private var visibleCaptions: [Caption] { session.captions(matching: query) }

    var body: some View {
        Group {
            if session.captions.isEmpty {
                ContentUnavailableView("这场会话没有字幕", systemImage: "captions.bubble")
            } else if visibleCaptions.isEmpty {
                ContentUnavailableView("没有匹配的字幕", systemImage: "magnifyingglass", description: Text("换一个词再搜。"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleCaptions) { caption in
                            captionRow(caption)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationTitle(session.createdAt.formatted(date: .abbreviated, time: .omitted))
        .navigationSubtitle(session.createdAt.formatted(date: .omitted, time: .shortened))
        .searchable(text: $query, prompt: "搜索英文或译文")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButton("复制全部", systemImage: "doc.on.doc", disabled: session.captions.isEmpty) {
                    copy(session.transcriptText)
                }
                if session.hasConsecutiveDuplicateEnglish {
                    toolbarButton("合并连续重复", systemImage: "arrow.triangle.merge") {
                        confirmCollapse = true
                    }
                }
                toolbarButton("导出文本", systemImage: "square.and.arrow.up", action: onExport)
                Button {
                    Task { await extract() }
                } label: {
                    if extracting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "text.book.closed")
                    }
                }
                .help(extracting ? "正在提取术语" : "提取术语")
                .disabled(extracting)
                .accessibilityLabel("提取术语")
                toolbarButton("删除", systemImage: "trash") {
                    onDelete()
                    dismiss()
                }
            }
        }
        .alert("术语候选", isPresented: Binding(
            get: { extractResult != nil },
            set: { if !$0 { extractResult = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(extractResult ?? "")
        }
        .alert("无法保存字幕", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .confirmationDialog("把连续相同的字幕收成一条？", isPresented: $confirmCollapse, titleVisibility: .visible) {
            Button("合并") { persist(session.collapsingConsecutiveDuplicates()) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只合并紧挨着、英文相同的字幕。隔开的句子会保留。")
        }
        .sheet(item: $editingCaption) { caption in
            CaptionEditSheet(caption: caption) { english, chinese in
                guard let updated = session.updating(captionID: caption.id, english: english, chinese: chinese) else {
                    throw CaptionEditFailure()
                }
                try onSave(updated)
                session = updated
            }
        }
    }

    private func persist(_ updated: CaptionSession) {
        do {
            try onSave(updated)
            session = updated
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func nextCaption(after caption: Caption) -> Caption? {
        guard let index = session.captions.firstIndex(where: { $0.id == caption.id }),
              index + 1 < session.captions.count else { return nil }
        return session.captions[index + 1]
    }

    /// 屏幕上的下一条必须就是时间上的下一条，避免搜索时把隔开的句子并到一起。
    private func canMerge(_ caption: Caption) -> Bool {
        guard let next = nextCaption(after: caption),
              let visibleIndex = visibleCaptions.firstIndex(where: { $0.id == caption.id }) else { return false }
        let following = visibleCaptions.index(after: visibleIndex)
        return following < visibleCaptions.endIndex && visibleCaptions[following].id == next.id
    }

    private func extract() async {
        extracting = true
        defer { extracting = false }
        extractResult = await onExtract()
    }

    private func captionRow(_ caption: Caption) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(caption.createdAt, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption.english)
                    .font(.body)
                if let chinese = caption.chinese, !chinese.isEmpty {
                    Text(chinese)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                captionActions(caption)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .help("修改或合并")
            .accessibilityLabel("修改或合并")
        }
        .padding(.vertical, 8)
        .contextMenu { captionActions(caption) }
    }

    @ViewBuilder
    private func captionActions(_ caption: Caption) -> some View {
        Button("修改") { editingCaption = caption }
        Button("与下一条合并") { merge(caption) }
            .disabled(!canMerge(caption))
        Divider()
        Button("复制") { copy(caption.transcriptLine) }
    }

    private func merge(_ caption: Caption) {
        guard let updated = session.mergingWithNext(captionID: caption.id) else { return }
        persist(updated)
    }

    private func toolbarButton(
        _ help: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .help(help)
        .disabled(disabled)
        .accessibilityLabel(help)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct CaptionEditFailure: LocalizedError {
    var errorDescription: String? { "这条字幕已经不在这场会话里。" }
}

private struct CaptionEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var english: String
    @State private var chinese: String
    @State private var errorMessage: String?
    let onSave: (String, String) throws -> Void

    init(caption: Caption, onSave: @escaping (String, String) throws -> Void) {
        _english = State(initialValue: caption.english)
        _chinese = State(initialValue: caption.chinese ?? "")
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("修改字幕")
                .font(.headline)
            TextField("英文", text: $english, axis: .vertical)
                .lineLimit(2...6)
            TextField("译文", text: $chinese, axis: .vertical)
                .lineLimit(2...6)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("存储") { commit() }
                    .disabled(english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func commit() {
        do {
            try onSave(english, chinese)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
