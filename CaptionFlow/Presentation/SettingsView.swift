import Carbon.HIToolbox
import Sparkle
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case launch, textAppearance, display, translation, models, shortcuts, vocabulary, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: return "启动"
        case .textAppearance: return "文本外观"
        case .display: return "显示设置"
        case .translation: return "翻译设置"
        case .models: return "模型"
        case .shortcuts: return "键盘快捷键"
        case .vocabulary: return "自定义词汇"
        case .updates: return "软件更新"
        case .about: return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .launch: return "power"
        case .textAppearance: return "textformat"
        case .display: return "rectangle.on.rectangle"
        case .translation: return "character.bubble"
        case .models: return "cpu"
        case .shortcuts: return "keyboard"
        case .vocabulary: return "textformat.abc"
        case .updates: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    let updater: SPUUpdater

    @State private var selection: SettingsSection? = .translation

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch selection ?? .translation {
            case .translation:
                TranslationSettingsPane()
            case .models:
                ModelSettingsPane()
            case .updates:
                UpdateSettingsPane(updater: updater)
            case .textAppearance:
                TextAppearanceSettingsPane()
            case .display:
                DisplaySettingsPane()
            case .shortcuts:
                ShortcutSettingsPane()
            case let other:
                PlaceholderSettingsPane(title: other.title)
            }
        }
        .frame(width: 720, height: 480)
    }
}

private struct PlaceholderSettingsPane: View {
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2)
            Text("即将推出")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}

private struct TextAppearanceSettingsPane: View {
    @AppStorage(CaptionOverlaySettings.translationFontSizeKey) private var translationFontSize = CaptionOverlaySettings.defaultTranslationFontSize
    @AppStorage(CaptionOverlaySettings.originalFontSizeKey) private var originalFontSize = CaptionOverlaySettings.defaultOriginalFontSize
    @AppStorage(CaptionOverlaySettings.showsOriginalKey) private var showsOriginal = true
    @AppStorage(CaptionOverlaySettings.textColorKey) private var textColorRaw = CaptionTextColor.white.rawValue

    var body: some View {
        Form {
            Section {
                LabeledContent("译文字号") {
                    Slider(value: $translationFontSize, in: 16...48, step: 1)
                    Text("\(Int(translationFontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("原文字号") {
                    Slider(value: $originalFontSize, in: 12...36, step: 1)
                    Text("\(Int(originalFontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Picker("文字颜色", selection: $textColorRaw) {
                    ForEach(CaptionTextColor.allCases) { color in
                        Text(color.displayName).tag(color.rawValue)
                    }
                }
                Toggle("显示英文原文", isOn: $showsOriginal)
            } header: {
                Text("悬浮字幕")
            } footer: {
                Text("修改会立即应用到悬浮字幕窗。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("文本外观")
    }
}

private struct DisplaySettingsPane: View {
    @AppStorage(CaptionOverlaySettings.backgroundOpacityKey) private var backgroundOpacity = CaptionOverlaySettings.defaultBackgroundOpacity
    @AppStorage(CaptionOverlaySettings.alwaysOnTopKey) private var alwaysOnTop = true
    @AppStorage(CaptionOverlaySettings.hidesOnStopKey) private var hidesOnStop = true

    var body: some View {
        Form {
            Section {
                LabeledContent("背景不透明度") {
                    Slider(value: $backgroundOpacity, in: 0...1)
                    Text("\(Int(backgroundOpacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Toggle("始终置顶", isOn: $alwaysOnTop)
                Toggle("停止字幕时隐藏字幕窗", isOn: $hidesOnStop)
            } header: {
                Text("悬浮字幕窗")
            } footer: {
                Text("拖动字幕窗可调整位置，拖动边缘可调整大小，位置会被记住。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("显示设置")
    }
}

private struct ShortcutSettingsPane: View {
    @AppStorage(GlobalHotKey.enabledKey) private var enabled = true
    @State private var recording: GlobalHotKey?
    @State private var message: String?
    /// 快捷键存在 UserDefaults 的 Data 里，没有 @AppStorage 触发刷新，修改后手动递增。
    @State private var revision = 0
    @State private var monitor: Any?

    var body: some View {
        Form {
            Section {
                Toggle("启用全局快捷键", isOn: $enabled)
            } footer: {
                Text("在任何应用中都可以使用这些快捷键。")
            }
            Section {
                ForEach(GlobalHotKey.allCases) { hotKey in
                    LabeledContent(hotKey.title) {
                        HStack(spacing: 6) {
                            Button(recording == hotKey ? "按下快捷键…" : hotKey.combo().displayString) {
                                recording == hotKey ? stopRecording() : startRecording(hotKey)
                            }
                            .font(.body.monospaced())
                            .frame(minWidth: 110)
                            Button {
                                hotKey.setCombo(nil)
                                message = nil
                                revision += 1
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("恢复默认")
                            .disabled(hotKey.combo() == hotKey.defaultCombo)
                        }
                    }
                }
                .id(revision)
            } footer: {
                if let message {
                    Text(message).foregroundStyle(.red)
                } else {
                    Text("点击快捷键后按下新的组合，需包含 ⌃、⌥ 或 ⌘；按 Esc 取消。")
                }
            }
            .disabled(!enabled)
        }
        .onDisappear(perform: stopRecording)
        .formStyle(.grouped)
        .navigationTitle("键盘快捷键")
    }

    private func startRecording(_ hotKey: GlobalHotKey) {
        stopRecording()
        recording = hotKey
        message = nil
        NotificationCenter.default.post(name: GlobalHotKey.recordingDidChangeNotification, object: nil, userInfo: ["isRecording": true])
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event, for: hotKey)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            NotificationCenter.default.post(name: GlobalHotKey.recordingDidChangeNotification, object: nil, userInfo: ["isRecording": false])
        }
        recording = nil
    }

    private func record(_ event: NSEvent, for hotKey: GlobalHotKey) {
        guard Int(event.keyCode) != kVK_Escape else {
            stopRecording()
            return
        }
        let combo = KeyCombo(
            keyCode: UInt32(event.keyCode),
            modifiers: KeyCombo.carbonModifiers(from: event.modifierFlags),
            keyLabel: Self.keyLabel(for: event)
        )
        if !combo.hasRequiredModifier {
            message = "快捷键需包含 ⌃、⌥ 或 ⌘。"
            return
        }
        if let other = hotKey.conflict(with: combo) {
            message = "\(combo.displayString) 已用于「\(other.title)」。"
            return
        }
        hotKey.setCombo(combo)
        revision += 1
        stopRecording()
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            // 功能键的 keyCode 不连续，逐个查表。
            let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
            if let index = functionKeys.firstIndex(of: Int(event.keyCode)) {
                return "F\(index + 1)"
            }
            return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}

private struct TranslationSettingsPane: View {
    @AppStorage("translation.targetLanguage") private var targetLanguageRaw = TargetLanguage.simplifiedChinese.rawValue
    @AppStorage("translation.engineMode") private var engineModeRaw = TranslationEngineMode.auto.rawValue

    var body: some View {
        Form {
            Section {
                Picker("目标语言", selection: $targetLanguageRaw) {
                    ForEach(TargetLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                Picker("翻译方式", selection: $engineModeRaw) {
                    ForEach(TranslationEngineMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
            } header: {
                Text("翻译")
            } footer: {
                Text("决定翻译目标语言、优先使用本地翻译还是 LLM；具体模型与 API Key 在“模型”中配置。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("翻译设置")
    }
}

private struct UpdateSettingsPane: View {
    let updater: SPUUpdater

    @State private var automaticallyChecks = false
    @State private var lastCheckDate: Date?

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("当前版本", value: versionText)
                Toggle("自动检查更新", isOn: $automaticallyChecks)
                    .onChange(of: automaticallyChecks) { _, isOn in
                        updater.automaticallyChecksForUpdates = isOn
                    }
                LabeledContent("上次检查") {
                    if let lastCheckDate {
                        Text(lastCheckDate, format: .dateTime)
                    } else {
                        Text("从未")
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    CheckForUpdatesView(updater: updater)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("软件更新")
        .onAppear {
            automaticallyChecks = updater.automaticallyChecksForUpdates
            lastCheckDate = updater.lastUpdateCheckDate
        }
    }
}

private struct ModelSettingsPane: View {
    @State private var profiles: [LLMProfile] = []
    @State private var selectedID: UUID?
    @State private var isPresentingAddModel = false
    @State private var editingProfile: LLMProfile?

    private let keychain = KeychainStore(service: "com.taihongteng.CaptionFlow")

    var body: some View {
        Form {
            if profiles.isEmpty {
                Section {
                    Text("还没有配置任何模型，点击“添加模型”开始。")
                        .foregroundStyle(.secondary)
                } header: {
                    header
                }
            } else {
                // 每个模型单独一个 Section，在 grouped Form 中各自成为一张圆角卡片。
                ForEach(profiles) { profile in
                    Section {
                        row(for: profile)
                    } header: {
                        if profile.id == profiles.first?.id {
                            header
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("模型")
        .onAppear(perform: load)
        .sheet(isPresented: $isPresentingAddModel) {
            ModelProfileSheet { profile, apiKey in add(profile, apiKey: apiKey ?? "") }
        }
        .sheet(item: $editingProfile) { profile in
            ModelProfileSheet(
                editing: profile,
                storedAPIKey: try? keychain.secret(for: profile.id.uuidString),
                onSave: update
            )
        }
    }

    private var header: some View {
        HStack {
            Text("使用自有 API Key 管理自定义模型。")
            Spacer()
            Button {
                isPresentingAddModel = true
            } label: {
                Label("添加模型", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.bottom, 4)
    }

    private func row(for profile: LLMProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                Text("\(profile.apiStyle.displayName) · \(profile.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { profile.id == selectedID },
                set: { isOn in if isOn { select(profile) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            Menu {
                Button("编辑…") { editingProfile = profile }
                Button("删除", role: .destructive) { delete(profile) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editingProfile = profile }
        .contextMenu {
            Button("编辑…") { editingProfile = profile }
            Button("删除", role: .destructive) { delete(profile) }
        }
    }

    private func load() {
        profiles = LLMProfileStore.load()
        selectedID = LLMProfileStore.selectedID ?? profiles.first?.id
    }

    private func select(_ profile: LLMProfile) {
        selectedID = profile.id
        LLMProfileStore.selectedID = profile.id
    }

    private func delete(_ profile: LLMProfile) {
        profiles.removeAll { $0.id == profile.id }
        LLMProfileStore.save(profiles)
        try? keychain.deleteSecret(for: profile.id.uuidString)
        if selectedID == profile.id {
            self.selectedID = profiles.first?.id
            LLMProfileStore.selectedID = profiles.first?.id
        }
    }

    private func update(_ profile: LLMProfile, apiKey: String?) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        LLMProfileStore.save(profiles)
        if let apiKey {
            try? keychain.save(secret: apiKey, for: profile.id.uuidString)
        }
    }

    private func add(_ profile: LLMProfile, apiKey: String) {
        profiles.append(profile)
        LLMProfileStore.save(profiles)
        try? keychain.save(secret: apiKey, for: profile.id.uuidString)
        if selectedID == nil {
            select(profile)
        }
    }
}

private struct ModelProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var apiStyleRaw: String
    @State private var baseURLString: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var errorMessage = ""
    @State private var testMessage = ""
    @State private var isTesting = false

    /// 编辑时为原配置；为 nil 表示添加新模型。
    private let editing: LLMProfile?
    private let storedAPIKey: String?
    /// 第二个参数为 nil 表示沿用已保存的 API Key。
    private let onSave: (LLMProfile, String?) -> Void

    init(editing: LLMProfile? = nil, storedAPIKey: String? = nil, onSave: @escaping (LLMProfile, String?) -> Void) {
        self.editing = editing
        self.storedAPIKey = storedAPIKey
        self.onSave = onSave
        _name = State(initialValue: editing?.name ?? "")
        _apiStyleRaw = State(initialValue: (editing?.apiStyle ?? .anthropic).rawValue)
        _baseURLString = State(initialValue: editing?.baseURL.absoluteString ?? "")
        _model = State(initialValue: editing?.model ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "添加模型" : "编辑模型")
                .font(.title2)

            Form {
                TextField("名称", text: $name)
                Picker("类型", selection: $apiStyleRaw) {
                    ForEach(LLMAPIStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                TextField("Base URL", text: $baseURLString)
                TextField("模型", text: $model)
                SecureField("API Key", text: $apiKey, prompt: Text(editing == nil ? "" : "留空则沿用已保存的 Key"))
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if !testMessage.isEmpty {
                Label(testMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            HStack {
                Button("测试连接") {
                    testConnection()
                }
                .disabled(isTesting)
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "添加模型" : "保存") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }

    /// 本次要使用的 API Key：输入了新值用新值，编辑时留空则用已保存的。
    private var effectiveAPIKey: String {
        apiKey.isEmpty ? (storedAPIKey ?? "") : apiKey
    }

    private func submit() {
        guard let profile = validatedProfile() else { return }
        onSave(profile, apiKey.isEmpty ? nil : apiKey)
        dismiss()
    }

    private func testConnection() {
        guard let profile = validatedProfile(),
              let configuration = LLMConfiguration(
                baseURL: profile.baseURL,
                model: profile.model,
                instruction: "Translate English speech into concise, natural subtitles."
              ) else { return }

        let translator = LLMTranslator(configuration: configuration, apiKey: effectiveAPIKey, style: profile.apiStyle)
        testMessage = ""
        isTesting = true
        Task {
            do {
                _ = try await translator.translate("Hello")
                testMessage = "连接成功"
            } catch LLMTranslatorError.httpStatus(let status) {
                errorMessage = "连接失败：HTTP \(status)，请检查 Base URL、模型名称和 API Key。"
            } catch {
                errorMessage = "连接失败：\(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    private func validatedProfile() -> LLMProfile? {
        errorMessage = ""
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请输入名称。"
            return nil
        }
        guard let baseURL = URL(string: baseURLString), baseURL.scheme?.lowercased() == "https" else {
            errorMessage = "请输入合法的 HTTPS Base URL。"
            return nil
        }
        guard !trimmedModel.isEmpty else {
            errorMessage = "请输入模型名称。"
            return nil
        }
        guard !effectiveAPIKey.isEmpty else {
            errorMessage = "请输入 API Key。"
            return nil
        }
        guard let apiStyle = LLMAPIStyle(rawValue: apiStyleRaw) else { return nil }

        return LLMProfile(id: editing?.id ?? UUID(), name: trimmedName, apiStyle: apiStyle, baseURL: baseURL, model: trimmedModel)
    }
}
