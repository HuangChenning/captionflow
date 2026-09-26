import AppKit
import Combine

@MainActor
final class CaptionSessionController: ObservableObject {
    @Published var sourceKind: AudioSourceKind = SavedAudioSource.load().kind {
        didSet { saveAudioSource() }
    }
    /// 系统音频只采集该应用；nil 为全部应用。
    @Published var systemAudioAppBundleID: String? = SavedAudioSource.load().appBundleID {
        didSet { saveAudioSource() }
    }
    @Published private(set) var isPreparing = false
    @Published private(set) var pipeline: CaptionPipeline?
    @Published private(set) var errorMessage: String?
    /// 本地翻译不可用、本次会话改用 LLM 或只显示英文时的说明。
    @Published private(set) var translationNotice: String?
    /// 可作为“单个应用”音频源的正在运行的应用。
    @Published private(set) var runningApps: [NSRunningApplication] = []

    private let translationSessionHolder: TranslationSessionHolder
    private let keychain = KeychainStore(service: "com.taihongteng.CaptionFlow")
    private let sessionStore = SessionStore()
    // Apple 翻译的会话需要挂在窗口里的视图上；没有主窗口后挂在字幕窗上。
    private lazy var overlay = CaptionOverlayWindowController(
        rootView: CaptionOverlayView(session: self)
            .background(AppleTranslationHostView(holder: translationSessionHolder))
    )
    private var pipelineStateObservation: AnyCancellable?
    private let hotKeys = GlobalHotKeys()

    init(translationSessionHolder: TranslationSessionHolder) {
        self.translationSessionHolder = translationSessionHolder
        applyHotKeySetting()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyHotKeySetting() }
        }
        NotificationCenter.default.addObserver(
            forName: GlobalHotKey.recordingDidChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let isRecording = notification.userInfo?["isRecording"] as? Bool ?? false
            MainActor.assumeIsolated {
                self?.isRecordingHotKey = isRecording
                self?.applyHotKeySetting()
            }
        }
        refreshRunningApps()
        // 启动时就检查本地翻译资源，菜单和设置页不必等到开始字幕才知道状态。
        let target = UserDefaults.standard.string(forKey: "translation.targetLanguage")
            .flatMap(TargetLanguage.init(rawValue:)) ?? .simplifiedChinese
        Task { await translationSessionHolder.readiness.refresh(target: target) }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunningApps() }
            }
        }
    }

    var needsScreenCapturePermission: Bool {
        errorMessage == AudioSourceError.screenCapturePermissionDenied.errorDescription
    }

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func toggleSession() async {
        if pipeline == nil {
            await start()
        } else {
            await stop()
        }
    }

    func toggleOverlay() {
        overlay.toggle()
    }

    func moveOverlayToNextScreen() {
        overlay.moveToNextScreen()
    }

    func start() async {
        guard pipeline == nil else { return }
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }
        overlay.show()

        do {
            let asr = try await WhisperKitEnglishASR.load()
            let translators = await makeTranslators()
            let newPipeline = CaptionPipeline(
                audioSource: sourceKind.makeSource(appBundleID: systemAudioAppBundleID),
                asr: asr,
                translator: translators.translator,
                refiner: translators.refiner
            )
            pipeline = newPipeline
            // 采集或识别失败时回到停止状态，原因显示在菜单和字幕窗里。
            pipelineStateObservation = newPipeline.$state.sink { [weak self] state in
                guard case .failed(let reason) = state else { return }
                MainActor.assumeIsolated { self?.handleFailure(reason) }
            }
            await newPipeline.start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        pipelineStateObservation = nil
        translationNotice = nil
        let captions = pipeline?.captions ?? []
        await pipeline?.stop()
        pipeline = nil
        if !captions.isEmpty {
            do { _ = try sessionStore.save(captions: captions) }
            catch { errorMessage = "无法保存字幕历史：\(error.localizedDescription)" }
        }
        let hidesOnStop = UserDefaults.standard.object(forKey: CaptionOverlaySettings.hidesOnStopKey) as? Bool ?? true
        if hidesOnStop {
            overlay.hide()
        }
    }

    private func saveAudioSource() {
        SavedAudioSource(kind: sourceKind, appBundleID: systemAudioAppBundleID).save()
    }

    private func handleFailure(_ reason: String) {
        pipelineStateObservation = nil
        pipeline = nil
        errorMessage = reason
        overlay.show()
    }

    private func refreshRunningApps() {
        let ownBundleID = Bundle.main.bundleIdentifier
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != ownBundleID }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        // 选中的应用已退出时回到全部系统音频，避免菜单里出现无效选项。
        if let selected = systemAudioAppBundleID,
           !runningApps.contains(where: { $0.bundleIdentifier == selected }) {
            systemAudioAppBundleID = nil
        }
    }

    /// 当前已注册的组合；nil 表示未注册。用于避免每次 UserDefaults 变化都重新注册。
    private var registeredCombos: [KeyCombo]?
    private var isRecordingHotKey = false

    private func applyHotKeySetting() {
        let enabled = UserDefaults.standard.object(forKey: GlobalHotKey.enabledKey) as? Bool ?? true
        let combos = GlobalHotKey.allCases.map { $0.combo() }
        let desired = enabled && !isRecordingHotKey ? combos : nil
        guard desired != registeredCombos else { return }
        registeredCombos = desired
        guard desired != nil else {
            hotKeys.unregisterAll()
            return
        }
        hotKeys.register(GlobalHotKey.allCases.map { hotKey in
            (combo: hotKey.combo(), action: { [weak self] in self?.perform(hotKey) })
        })
    }

    private func perform(_ hotKey: GlobalHotKey) {
        switch hotKey {
        case .toggleCaptions: Task { await toggleSession() }
        case .toggleOverlay: toggleOverlay()
        case .moveOverlayToNextScreen: overlay.moveToNextScreen()
        case .switchAudioSource: switchAudioSource()
        }
    }

    private func switchAudioSource() {
        guard pipeline == nil, !isPreparing else { return }
        sourceKind = sourceKind == .microphone ? .systemAudio : .microphone
    }

    /// 自动模式下本地翻译先显示，LLM 结果到达后替换（refiner）。
    /// 本地资源未就绪时不使用本地翻译，改用 LLM 或只显示英文，并通过 translationNotice 说明原因。
    private func makeTranslators() async -> (translator: Translator?, refiner: CaptionRefiner?) {
        let defaults = UserDefaults.standard
        let instruction = defaults.string(forKey: "llm.instruction")
            ?? "Translate English speech into concise, natural subtitles."
        let targetLanguage = defaults.string(forKey: "translation.targetLanguage")
            .flatMap(TargetLanguage.init(rawValue:)) ?? .simplifiedChinese
        let engineMode = defaults.string(forKey: "translation.engineMode")
            .flatMap(TranslationEngineMode.init(rawValue:)) ?? .auto

        translationSessionHolder.updateTarget(targetLanguage.locale)
        let readiness = translationSessionHolder.readiness
        await readiness.refresh(target: targetLanguage)

        let llmTranslator = makeLLMTranslator(instruction: instruction, targetLanguage: targetLanguage)
        let route = engineMode.route(localReady: readiness.isReady, llmAvailable: llmTranslator != nil)
        translationNotice = Self.notice(for: route, mode: engineMode, readiness: readiness.state, target: targetLanguage)

        let local = AppleTranslator(holder: translationSessionHolder)
        switch route {
        case .localThenLLM: return (local, llmTranslator)
        case .localOnly: return (local, nil)
        case .llmOnly: return (llmTranslator, nil)
        case .englishOnly: return (nil, nil)
        }
    }

    private func makeLLMTranslator(instruction: String, targetLanguage: TargetLanguage) -> LLMTranslator? {
        guard let selectedID = LLMProfileStore.selectedID,
              let profile = LLMProfileStore.load().first(where: { $0.id == selectedID }),
              let apiKey = try? keychain.secret(for: selectedID.uuidString), !apiKey.isEmpty,
              let configuration = LLMConfiguration(baseURL: profile.baseURL, model: profile.model, instruction: instruction) else {
            return nil
        }
        return LLMTranslator(
            configuration: configuration,
            apiKey: apiKey,
            style: profile.apiStyle,
            targetLanguageName: targetLanguage.displayName,
            glossary: (try? GlossaryStore().load()) ?? []
        )
    }

    /// 本地翻译本应参与却因资源不可用被跳过时给出的说明；其余情况返回 nil。
    static func notice(
        for route: TranslationRoute,
        mode: TranslationEngineMode,
        readiness: LocalTranslationReadiness.State,
        target: TargetLanguage
    ) -> String? {
        let fallback: String
        switch route {
        case .localThenLLM, .localOnly: return nil
        case .llmOnly:
            // 用户选了仅 LLM 时本来就不用本地翻译，无需提示。
            guard mode != .llmOnly else { return nil }
            fallback = "本次使用 LLM 翻译。"
        case .englishOnly:
            fallback = "本次只显示英文字幕。"
        }
        let pair = "英语到\(target.displayName)"
        switch readiness {
        case .downloadable: return "\(pair)的本地翻译资源尚未下载，\(fallback)可在“翻译设置”中下载。"
        case .unsupported: return "此设备不支持\(pair)的本地翻译，\(fallback)"
        case .failed(let reason): return "本地翻译资源检查失败：\(reason)。\(fallback)"
        case .checking, .installed: return "\(pair)的本地翻译暂不可用，\(fallback)"
        }
    }
}
