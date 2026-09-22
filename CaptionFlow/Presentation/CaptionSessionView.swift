import SwiftUI

struct CaptionSessionView: View {
    @ObservedObject var pipeline: CaptionPipeline

    var body: some View {
        VStack(spacing: 0) {
            if case .failed(let reason) = pipeline.state {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.red)
            }
            CaptionListView(captions: pipeline.captions)
        }
    }
}
