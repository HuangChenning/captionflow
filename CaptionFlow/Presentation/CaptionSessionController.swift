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
        let instruction = defaults.string(forKey: "llm.instruction")
            ?? "Translate English speech into concise, natural subtitles."
        let targetLanguage = defaults.string(forKey: "translation.targetLanguage")
            .flatMap(TargetLanguage.init(rawValue:)) ?? .simplifiedChinese
        let engineMode = defaults.string(forKey: "translation.engineMode")
            .flatMap(TranslationEngineMode.init(rawValue:)) ?? .auto

        translationSessionHolder.updateTarget(targetLanguage.locale)
        let fallback = AppleTranslator(holder: translationSessionHolder)

        guard engineMode != .localOnly else { return fallback }

        guard let selectedID = LLMProfileStore.selectedID,
              let profile = LLMProfileStore.load().first(where: { $0.id == selectedID }),
              let apiKey = try? keychain.secret(for: selectedID.uuidString), !apiKey.isEmpty,
              let configuration = LLMConfiguration(baseURL: profile.baseURL, model: profile.model, instruction: instruction) else {
            return fallback
        }

        let llmTranslator = LLMTranslator(
            configuration: configuration,
            apiKey: apiKey,
            style: profile.apiStyle,
            targetLanguageName: targetLanguage.displayName
        )

        return engineMode == .llmOnly ? llmTranslator : FallbackTranslator(primary: llmTranslator, fallback: fallback)
    }
}
