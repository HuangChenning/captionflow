import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case launch, textAppearance, display, translation, models, shortcuts, vocabulary, about

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
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
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

private struct ModelSettingsPane: View {
    @State private var profiles: [LLMProfile] = []
    @State private var selectedID: UUID?
    @State private var isPresentingAddModel = false

    private let keychain = KeychainStore(service: "com.taihongteng.CaptionFlow")

    var body: some View {
        Form {
            Section {
                if profiles.isEmpty {
                    Text("还没有配置任何模型，点击右上角“添加模型”开始。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
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
                                Button("删除", role: .destructive) { delete(profile) }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .contextMenu {
                            Button("删除", role: .destructive) { delete(profile) }
                        }
                    }
                }
            } header: {
                Text("已配置的模型")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("模型")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingAddModel = true
                } label: {
                    Label("添加模型", systemImage: "plus")
                }
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $isPresentingAddModel) {
            AddModelSheet(onAdd: add)
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

    private func add(_ profile: LLMProfile, apiKey: String) {
        profiles.append(profile)
        LLMProfileStore.save(profiles)
        try? keychain.save(secret: apiKey, for: profile.id.uuidString)
        if selectedID == nil {
            select(profile)
        }
    }
}

private struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var apiStyleRaw = LLMAPIStyle.anthropic.rawValue
    @State private var baseURLString = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var errorMessage = ""

    let onAdd: (LLMProfile, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加模型")
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
                SecureField("API Key", text: $apiKey)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("添加模型") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请输入名称。"
            return
        }
        guard let baseURL = URL(string: baseURLString), baseURL.scheme?.lowercased() == "https" else {
            errorMessage = "请输入合法的 HTTPS Base URL。"
            return
        }
        guard !trimmedModel.isEmpty else {
            errorMessage = "请输入模型名称。"
            return
        }
        guard !apiKey.isEmpty else {
            errorMessage = "请输入 API Key。"
            return
        }
        guard let apiStyle = LLMAPIStyle(rawValue: apiStyleRaw) else { return }

        let profile = LLMProfile(name: trimmedName, apiStyle: apiStyle, baseURL: baseURL, model: trimmedModel)
        onAdd(profile, apiKey)
        dismiss()
    }
}
