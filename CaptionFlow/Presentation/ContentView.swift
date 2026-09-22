import SwiftUI

struct ContentView: View {
    @StateObject private var controller: CaptionSessionController

    init(translationSessionHolder: TranslationSessionHolder) {
        _controller = StateObject(wrappedValue: CaptionSessionController(translationSessionHolder: translationSessionHolder))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.red)
            }
            if let pipeline = controller.pipeline {
                CaptionSessionView(pipeline: pipeline)
            } else {
                CaptionListView(captions: [])
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var toolbar: some View {
        HStack {
            Picker("Source", selection: $controller.sourceKind) {
                ForEach(AudioSourceKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .disabled(controller.pipeline != nil || controller.isPreparing)

            Spacer()

            if controller.isPreparing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button(controller.pipeline == nil ? "Start" : "Stop") {
                Task {
                    if controller.pipeline == nil {
                        await controller.start()
                    } else {
                        await controller.stop()
                    }
                }
            }
            .disabled(controller.isPreparing)

            SettingsLink {
                Image(systemName: "gearshape")
            }
        }
        .padding()
    }
}
