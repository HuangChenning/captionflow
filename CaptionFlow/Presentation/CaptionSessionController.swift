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
    /// 可作为“单个应用”音频源的正在运行的应用。
    @Published private(set) var runningApps: [NSRunningApplication] = []

    private let translationSessionHolder: TranslationSessionHolder
    private let keychain = KeychainStore(service: "com.taihongteng.CaptionFlow")
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
            let newPipeline = CaptionPipeline(
                audioSource: sourceKind.makeSource(appBundleID: systemAudioAppBundleID),
                asr: asr,
                translator: makeTranslator()
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
        await pipeline?.stop()
        pipeline = nil
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
