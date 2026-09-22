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
