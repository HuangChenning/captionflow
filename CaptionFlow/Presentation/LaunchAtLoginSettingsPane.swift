import ServiceManagement
import SwiftUI

struct LaunchAtLoginSettingsPane: View {
    @State private var enabled = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("登录后自动启动 CaptionFlow", isOn: Binding(
                    get: { enabled },
                    set: { update($0) }
                ))
            } footer: {
                Text("可在系统设置的“登录项与扩展”中管理此项。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("启动")
        .onAppear { enabled = SMAppService.mainApp.status == .enabled }
        .alert("无法更新登录项", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func update(_ wantsEnabled: Bool) {
        do {
            if wantsEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            enabled = SMAppService.mainApp.status == .enabled
        } catch {
            enabled = SMAppService.mainApp.status == .enabled
            errorMessage = error.localizedDescription
        }
    }
}
