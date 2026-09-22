import SwiftUI

struct SettingsView: View {
    @AppStorage("llm.apiStyle") private var apiStyleRaw = LLMAPIStyle.anthropic.rawValue
    @AppStorage("llm.baseURL") private var baseURLString = "https://api.minimaxi.com/anthropic"
    @AppStorage("llm.model") private var model = "MiniMax-M3"
    @AppStorage("llm.instruction") private var instruction = "Translate English speech into concise, natural Simplified Chinese subtitles."

    @State private var apiKey = ""
    @State private var status = ""

    @Environment(\.dismiss) private var dismiss

    private let keychain = KeychainStore(service: "com.taihongteng.CaptionFlow")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
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
        .frame(minWidth: 480, minHeight: 300)
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
