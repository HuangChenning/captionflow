import Sparkle
import SwiftUI

@main
struct CaptionFlowApp: App {
    @StateObject private var translationSessionHolder = TranslationSessionHolder()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView(translationSessionHolder: translationSessionHolder)
                .background(AppleTranslationHostView(holder: translationSessionHolder))
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
        Settings {
            SettingsView(updater: updaterController.updater)
        }
        .windowResizability(.contentSize)
    }
}
