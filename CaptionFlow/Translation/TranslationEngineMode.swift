import Foundation

enum TranslationEngineMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case localOnly
    case llmOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .localOnly: return "仅本地"
        case .llmOnly: return "仅大模型"
        }
    }
}

/// 一次字幕会话实际使用的翻译方式。
enum TranslationRoute: Equatable {
    /// 本地译文先显示，LLM 结果到达后替换。
    case localThenLLM
    case localOnly
    case llmOnly
    /// 本地资源不可用且没有可用的 LLM：只显示英文字幕。
    case englishOnly
}

extension TranslationEngineMode {
    /// 本地资源未安装时不走本地翻译，否则翻译会卡在系统下载提示上。
    func route(localReady: Bool, llmAvailable: Bool) -> TranslationRoute {
        switch self {
        case .auto:
            switch (localReady, llmAvailable) {
            case (true, true): return .localThenLLM
            case (true, false): return .localOnly
            case (false, true): return .llmOnly
            case (false, false): return .englishOnly
            }
        case .localOnly:
            return localReady ? .localOnly : .englishOnly
        case .llmOnly:
            if llmAvailable { return .llmOnly }
            return localReady ? .localOnly : .englishOnly
        }
    }
}
