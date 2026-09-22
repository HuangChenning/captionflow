import Foundation

@MainActor
final class CaptionPipeline: ObservableObject {
    @Published private(set) var state: AppSessionState = .idle
    @Published private(set) var captions: [Caption] = []

    private let audioSource: AudioSource
    private let asr: EnglishASR
    private let translator: Translator
    private let minChunkSamples: Int

    private(set) var pumpTask: Task<Void, Never>?

    init(
        audioSource: AudioSource,
        asr: EnglishASR,
        translator: Translator,
        minChunkDuration: TimeInterval = 3,
        sampleRate: Double = 16_000
    ) {
        self.audioSource = audioSource
        self.asr = asr
        self.translator = translator
        self.minChunkSamples = Int(minChunkDuration * sampleRate)
    }

    func start() async {
        guard state == .idle else { return }
        state = .requestingPermission
        do {
            let stream = try await audioSource.start()
            state = .running
            pumpTask = Task { [weak self] in
                await self?.pump(stream)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard state == .running else { return }
        state = .stopping
        pumpTask?.cancel()
        pumpTask = nil
        await audioSource.stop()
        state = .idle
    }

    private func pump(_ stream: AsyncStream<[Float]>) async {
        var buffer: [Float] = []
        for await chunk in stream {
            if Task.isCancelled { return }
            buffer.append(contentsOf: chunk)
            guard buffer.count >= minChunkSamples else { continue }
            let samples = buffer
            buffer.removeAll()
            await transcribeAndTranslate(samples)
        }
    }

    private func transcribeAndTranslate(_ samples: [Float]) async {
        do {
            let english = try await asr.transcribe(samples: samples)
            guard !english.isEmpty, !isNonSpeechTranscript(english) else { return }

            let caption = Caption(id: UUID(), english: english, chinese: nil, isProvisional: true, createdAt: .now)
            captions.append(caption)

            let chinese = try await translator.translate(english)
            updateCaption(id: caption.id, chinese: chinese)
        } catch {
            await fail(error)
        }
    }

    private func updateCaption(id: UUID, chinese: String) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        let existing = captions[index]
        captions[index] = Caption(
            id: id,
            english: existing.english,
            chinese: chinese,
            isProvisional: false,
            createdAt: existing.createdAt
        )
    }

    private func fail(_ error: Error) async {
        pumpTask?.cancel()
        pumpTask = nil
        await audioSource.stop()
        state = .failed(error.localizedDescription)
    }
}
