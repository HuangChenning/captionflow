import AppKit
import Sparkle
import SwiftUI

/// 菜单栏图标的菜单，承担原主窗口的全部操作。
struct MenuBarMenu: View {
    @ObservedObject var controller: CaptionSessionController
    let updater: SPUUpdater
    @AppStorage("translation.targetLanguage") private var targetLanguageRaw = TargetLanguage.simplifiedChinese.rawValue
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let errorMessage = controller.errorMessage {
            Text(errorMessage)
            if controller.needsScreenCapturePermission {
                Button("打开「录屏与系统录音」设置…", action: controller.openScreenCaptureSettings)
            }
            Divider()
        }

        Button(sessionButtonTitle) {
            Task { await controller.toggleSession() }
        }
        .disabled(controller.isPreparing)
        Button("显示 / 隐藏字幕窗", action: controller.toggleOverlay)
        Button("字幕窗移到下一块屏幕", action: controller.moveOverlayToNextScreen)

        Divider()

        Picker("目标语言", selection: $targetLanguageRaw) {
            ForEach(TargetLanguage.allCases) { language in
                Text(language.displayName).tag(language.rawValue)
            }
        }
        Picker("音频源", selection: sourceSelection) {
            Text("麦克风").tag(SourceSelection.microphone)
            Text("全部系统音频").tag(SourceSelection.systemAudio(appBundleID: nil))
            if !controller.runningApps.isEmpty {
                Section("单个应用") {
                    ForEach(controller.runningApps, id: \.processIdentifier) { app in
                        Text(app.localizedName ?? app.bundleIdentifier ?? "")
                            .tag(SourceSelection.systemAudio(appBundleID: app.bundleIdentifier))
                    }
                }
            }
        }
        .disabled(controller.pipeline != nil || controller.isPreparing)

        Divider()

        CheckForUpdatesView(updater: updater)
        Button("CaptionFlow 设置…") {
            // 菜单栏应用不在前台，先激活，设置窗口才不会被其他窗口挡住。
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("退出 CaptionFlow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var sessionButtonTitle: String {
        if controller.isPreparing { return "准备中…" }
        return controller.pipeline == nil ? "开启实时字幕" : "停止实时字幕"
    }

    private enum SourceSelection: Hashable {
        case microphone
        /// nil 为全部系统音频。
        case systemAudio(appBundleID: String?)
    }

    private var sourceSelection: Binding<SourceSelection> {
        Binding(
            get: {
                controller.sourceKind == .microphone
                    ? .microphone
                    : .systemAudio(appBundleID: controller.systemAudioAppBundleID)
            },
            set: { selection in
                switch selection {
                case .microphone:
                    controller.sourceKind = .microphone
                case .systemAudio(let appBundleID):
                    controller.sourceKind = .systemAudio
                    controller.systemAudioAppBundleID = appBundleID
                }
            }
        )
    }
}
