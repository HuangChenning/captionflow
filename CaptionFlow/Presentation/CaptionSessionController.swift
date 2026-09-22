import Foundation

@MainActor
final class CaptionSessionController: ObservableObject {
    @Published var sourceKind: AudioSourceKind = .microphone
    @Published private(set) var isPreparing = false
    @Published private(set) var pipeline: CaptionPipeline?
    @Published private(set) var errorMessage: String?

    private let translationSessionHolder: TranslationSessionHolder
    private let keychain = KeychainStore(service: "com.taihongteng.CaptionFlow")

    init(translationSessionHolder: TranslationSessionHolder) {
        self.translationSessionHolder = translationSessionHolder
    }

    func start() async {
        guard pipeline == nil else { return }
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }

        do {
            let asr = try await WhisperKitEnglishASR.load()
            let newPipeline = CaptionPipeline(
                audioSource: sourceKind.makeSource(),
                asr: asr,
                translator: makeTranslator()
            )
            pipeline = newPipeline
            await newPipeline.start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        await pipeline?.stop()
        pipeline = nil
    }

    private func makeTranslator() -> Translator {
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: "llm.apiStyle").flatMap(LLMAPIStyle.init(rawValue:)) ?? .anthropic
        let baseURLString = defaults.string(forKey: "llm.baseURL") ?? "https://api.minimaxi.com/anthropic"
        let model = defaults.string(forKey: "llm.model") ?? "MiniMax-M3"
        let instruction = defaults.string(forKey: "llm.instruction")
            ?? "Translate English speech into concise, natural subtitles."
        let apiKey = (try? keychain.secret(for: "default")) ?? ""
        let targetLanguage = defaults.string(forKey: "translation.targetLanguage")
            .flatMap(TargetLanguage.init(rawValue:)) ?? .simplifiedChinese

        translationSessionHolder.updateTarget(targetLanguage.locale)

        let fallback = AppleTranslator(holder: translationSessionHolder)
        guard let baseURL = URL(string: baseURLString),
              let configuration = LLMConfiguration(baseURL: baseURL, model: model, instruction: instruction) else {
            return fallback
        }
        return FallbackTranslator(
            primary: LLMTranslator(
                configuration: configuration,
                apiKey: apiKey,
                style: style,
                targetLanguageName: targetLanguage.displayName
            ),
            fallback: fallback
        )
    }
}
