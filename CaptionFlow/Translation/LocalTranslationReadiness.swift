import Foundation
import SwiftUI
import Translation

@available(macOS 15.0, *)
@MainActor
final class LocalTranslationReadiness: ObservableObject {
    enum State: Equatable { case checking, installed, downloadable, unsupported, failed(String) }
    @Published private(set) var state: State = .checking

    func refresh() async {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "zh-Hans")
        )
        switch status {
        case .installed: state = .installed
        case .supported: state = .downloadable
        case .unsupported: state = .unsupported
        @unknown default: state = .unsupported
        }
    }

    func prepare(using session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            await refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
