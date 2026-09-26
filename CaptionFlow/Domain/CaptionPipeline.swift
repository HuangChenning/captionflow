import Foundation

@MainActor
final class CaptionPipeline: ObservableObject {
    @Published private(set) var state: AppSessionState = .idle
    @Published private(set) var captions: [Caption] = []

    private let audioSource: AudioSource
    private let asr: EnglishASR
    private let translator: Translator
    /// 设置后，translator 的结果先作为临时译文显示，refiner 的结果到达后替换它。
    private let refiner: CaptionRefiner?
    private let minChunkSamples: Int

    private(set) var pumpTask: Task<Void, Never>?
    private(set) var refineTasks: [UUID: Task<Void, Never>] = [:]

    init(
        audioSource: AudioSource,
        asr: EnglishASR,
        translator: Translator,
        refiner: CaptionRefiner? = nil,
        minChunkDuration: TimeInterval = 3,
        sampleRate: Double = 16_000
    ) {
        self.audioSource = audioSource
        self.asr = asr
        self.translator = translator
        self.refiner = refiner
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
        cancelRefinements()
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

            guard let refiner else {
                let chinese = try await translator.translate(english)
                updateCaption(id: caption.id, chinese: chinese, isProvisional: false)
                return
            }
            let draft = try? await translator.translate(english)
            if let draft {
                updateCaption(id: caption.id, chinese: draft, isProvisional: true)
            }
            // 在后台等待 refiner，慢或卡住的请求不会挡住后面的语音。
            refineTasks[caption.id] = Task { [weak self] in
                let result: Result<String, Error>
                do {
                    result = .success(try await refiner.refine(english: english, localDraft: draft))
                } catch {
                    result = .failure(error)
                }
                self?.finishRefinement(id: caption.id, result: result)
            }
        } catch {
            await fail(error)
        }
    }

    private func finishRefinement(id: UUID, result: Result<String, Error>) {
        refineTasks[id] = nil
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let chinese):
            updateCaption(id: id, chinese: chinese, isProvisional: false)
        case .failure(let error):
            // 保留临时译文；两种翻译都没有结果时才停止。
            if let draft = captions.first(where: { $0.id == id })?.chinese {
                updateCaption(id: id, chinese: draft, isProvisional: false)
            } else {
                Task { await fail(error) }
            }
        }
    }

    private func cancelRefinements() {
        refineTasks.values.forEach { $0.cancel() }
        refineTasks.removeAll()
    }

    private func updateCaption(id: UUID, chinese: String, isProvisional: Bool) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        let existing = captions[index]
        captions[index] = Caption(
            id: id,
            english: existing.english,
            chinese: chinese,
            isProvisional: isProvisional,
            createdAt: existing.createdAt
        )
    }

    private func fail(_ error: Error) async {
        pumpTask?.cancel()
        pumpTask = nil
        cancelRefinements()
        await audioSource.stop()
        state = .failed(error.localizedDescription)
    }
}
