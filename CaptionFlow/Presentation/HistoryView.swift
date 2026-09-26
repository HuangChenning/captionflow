import AppKit
import SwiftUI

struct HistoryView: View {
    @State private var sessions: [CaptionSession] = []
    @State private var errorMessage: String?
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
                    Text("\(session.captions.count) 条字幕")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("导出文本…") { export(session) }
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

    private func export(_ session: CaptionSession) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CaptionFlow-\(session.id.uuidString).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportText(sessionID: session.id, to: url) }
        catch { errorMessage = error.localizedDescription }
    }
}
