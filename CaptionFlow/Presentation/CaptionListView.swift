import SwiftUI

struct CaptionListView: View {
    let captions: [Caption]

    var body: some View {
        if captions.isEmpty {
            VStack {
                Spacer()
                Text("Captions will appear here once audio is detected.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(captions) { caption in
                            CaptionRowView(caption: caption)
                                .id(caption.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: captions.last?.id) { _, newID in
                    guard let newID else { return }
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct CaptionRowView: View {
    let caption: Caption

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption.english)
                .font(.body)
                .foregroundStyle(caption.isProvisional ? .secondary : .primary)
            if let chinese = caption.chinese {
                Text(chinese)
                    .font(.title3)
                    .foregroundStyle(caption.isProvisional ? .secondary : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
