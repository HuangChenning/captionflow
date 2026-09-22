import SwiftUI

@main
struct CaptionFlowApp: App {
    @StateObject private var translationSessionHolder = TranslationSessionHolder()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(AppleTranslationHostView(holder: translationSessionHolder))
        }
    }
}

private struct ContentView: View {
    var body: some View {
        Text("CaptionFlow")
            .frame(minWidth: 360, minHeight: 240)
    }
}
