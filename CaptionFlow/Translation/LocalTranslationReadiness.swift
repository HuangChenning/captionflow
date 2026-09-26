import Foundation
import SwiftUI
import Translation

@available(macOS 15.0, *)
@MainActor
final class LocalTranslationReadiness: ObservableObject {
    enum State: Equatable { case checking, installed, downloadable, unsupported, failed(String) }
    typealias StatusCheck = @Sendable (Locale.Language, Locale.Language) async -> LanguageAvailability.Status

    @Published private(set) var state: State = .checking
    /// 检查的目标语言；跟随设置中选择的翻译目标语言。
    @Published private(set) var target: TargetLanguage = .simplifiedChinese
    private let checkStatus: StatusCheck

    init(checkStatus: @escaping StatusCheck = { await LanguageAvailability().status(from: $0, to: $1) }) {
        self.checkStatus = checkStatus
    }

    var isReady: Bool { state == .installed }

    func refresh(target: TargetLanguage) async {
        self.target = target
        await refresh()
    }

    func refresh() async {
        let checkedTarget = target
        let status = await checkStatus(Locale.Language(identifier: "en"), checkedTarget.locale)
        // 检查期间目标语言变了时，旧结果不能覆盖新语言的状态。
        guard checkedTarget == target else { return }
        switch status {
        case .installed: state = .installed
        case .supported: state = .downloadable
        case .unsupported: state = .unsupported
        @unknown default: state = .unsupported
        }
    }

    /// 执行下载（通常是 `TranslationSession.prepareTranslation()`），完成后重新检查，而不是假定已经装好。
    func prepare(_ download: () async throws -> Void) async {
        do {
            try await download()
            await refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
