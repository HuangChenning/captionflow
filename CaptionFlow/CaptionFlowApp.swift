import SwiftUI

@main
struct CaptionFlowApp: App {
    @StateObject private var translationSessionHolder = TranslationSessionHolder()

    var body: some Scene {
        WindowGroup {
            ContentView(translationSessionHolder: translationSessionHolder)
                .background(AppleTranslationHostView(holder: translationSessionHolder))
        }
    }
}
