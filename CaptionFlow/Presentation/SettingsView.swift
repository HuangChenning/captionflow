import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case launch, textAppearance, display, translation, shortcuts, vocabulary, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: return "启动"
        case .textAppearance: return "文本外观"
        case .display: return "显示设置"
        case .translation: return "翻译设置"
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
            case let other:
                PlaceholderSettingsPane(title: other.title)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
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
    @AppStorage("llm.apiStyle") private var apiStyleRaw = LLMAPIStyle.anthropic.rawValue
    @AppStorage("llm.baseURL") private var baseURLString = "https://api.minimaxi.com/anthropic"
    @AppStorage("llm.model") private var model = "MiniMax-M3"
    @AppStorage("llm.instruction") private var instruction = "Translate English speech into concise, natural subtitles."
    @AppStorage("translation.targetLanguage") private var targetLanguageRaw = TargetLanguage.simplifiedChinese.rawValue

    @State private var apiKey = ""
    @State private var status = ""

    @Environment(\.dismiss) private var dismiss

    private let keychain = KeychainStore(service: "com.taihongteng.CaptionFlow")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section("翻译") {
                    Picker("目标语言", selection: $targetLanguageRaw) {
                        ForEach(TargetLanguage.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                }
                Section("LLM") {
                    Picker("API Style", selection: $apiStyleRaw) {
                        ForEach(LLMAPIStyle.allCases) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    TextField("Base URL", text: $baseURLString)
                    TextField("Model", text: $model)
                    TextEditor(text: $instruction)
                        .frame(minHeight: 72)
                }
                Section("API Key") {
                    SecureField("Stored only in Keychain", text: $apiKey)
                }
            }
            HStack {
                Text(status)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Done") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding(.top)
        .navigationTitle("翻译设置")
        .onAppear {
            apiKey = (try? keychain.secret(for: "default")) ?? ""
        }
    }

    private func save() {
        guard let baseURL = URL(string: baseURLString),
              let configuration = LLMConfiguration(baseURL: baseURL, model: model, instruction: instruction) else {
            status = "Use an HTTPS URL and a model name."
            return
        }
        baseURLString = configuration.baseURL.absoluteString
        model = configuration.model
        instruction = configuration.instruction
        do {
            try keychain.save(secret: apiKey, for: "default")
            status = "Saved securely."
        } catch {
            status = "Could not save the API key."
        }
    }
}
