import SwiftUI

@main
struct CaptionFlowApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        Text("CaptionFlow")
            .frame(minWidth: 360, minHeight: 240)
    }
}
