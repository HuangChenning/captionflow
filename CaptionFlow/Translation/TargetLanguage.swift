import Foundation

enum TargetLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case russian = "ru"
    case portuguese = "pt"
    case arabic = "ar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: return "中文(简体)"
        case .traditionalChinese: return "中文(繁体)"
        case .japanese: return "日语"
        case .korean: return "韩语"
        case .spanish: return "西班牙语"
        case .french: return "法语"
        case .german: return "德语"
        case .russian: return "俄语"
        case .portuguese: return "葡萄牙语"
        case .arabic: return "阿拉伯语"
        }
    }

    var locale: Locale.Language {
        Locale.Language(identifier: rawValue)
    }
}
