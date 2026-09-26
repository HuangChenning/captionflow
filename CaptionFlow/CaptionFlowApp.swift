import AppKit
import Sparkle
import SwiftUI

@main
struct CaptionFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // 由 App 持有，全局快捷键、菜单栏菜单和悬浮字幕窗共用同一个会话。
    @StateObject private var sessionController: CaptionSessionController
    private let translationSessionHolder: TranslationSessionHolder
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        let holder = TranslationSessionHolder()
        translationSessionHolder = holder
        _sessionController = StateObject(wrappedValue: CaptionSessionController(translationSessionHolder: holder))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(controller: sessionController, updater: updaterController.updater)
        } label: {
            Image(systemName: sessionController.pipeline == nil ? "captions.bubble" : "captions.bubble.fill")
        }
        Settings {
            SettingsView(updater: updaterController.updater, translationSessionHolder: translationSessionHolder)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 点击 Dock 图标且没有打开的窗口时，打开设置窗口；菜单栏图标被挤掉时仍有入口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // SwiftUI 不再响应 showSettingsWindow:，改为触发 app 菜单里的「设置…」（⌘,）。
        if !hasVisibleWindows,
           let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) {
            appMenu.performActionForItem(at: index)
        }
        return true
    }
}
