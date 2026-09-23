import SwiftUI
import Translation

@available(macOS 15.0, *)
@MainActor
final class TranslationSessionHolder: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    private var session: TranslationSession?
    private var waiters: [CheckedContinuation<TranslationSession, Never>] = []

    init(source: Locale.Language = Locale.Language(identifier: "en"),
         target: Locale.Language = Locale.Language(identifier: "zh-Hans")) {
        configuration = TranslationSession.Configuration(source: source, target: target)
    }

    func attach(_ session: TranslationSession) {
        self.session = session
        waiters.forEach { $0.resume(returning: session) }
        waiters.removeAll()
    }

    func updateTarget(_ language: Locale.Language) {
        // 目标语言不变时保留现有会话：相同配置不会让 translationTask 重新提供会话，清空后翻译会一直等待。
        guard let source = configuration?.source, configuration?.target != language else { return }
        session = nil
        configuration = TranslationSession.Configuration(source: source, target: language)
    }

    func session() async -> TranslationSession {
        if let session { return session }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

@available(macOS 15.0, *)
struct AppleTranslationHostView: View {
    @ObservedObject var holder: TranslationSessionHolder

    var body: some View {
        Color.clear
            .translationTask(holder.configuration) { session in
                await holder.attach(session)
            }
    }
}

@available(macOS 15.0, *)
struct AppleTranslator: Translator {
    let holder: TranslationSessionHolder

    func translate(_ text: String) async throws -> String {
        let session = await holder.session()
        let response = try await session.translate(text)
        return response.targetText
    }
}
