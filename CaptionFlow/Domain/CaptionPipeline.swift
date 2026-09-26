import Foundation
import os

private let logger = Logger(subsystem: "com.taihongteng.CaptionFlow", category: "Pipeline")

@MainActor
final class CaptionPipeline: ObservableObject {
    @Published private(set) var state: AppSessionState = .idle
    @Published private(set) var captions: [Caption] = []
    /// 最近一次翻译失败的原因；翻译失败时保留英文字幕，不停止会话。下一次翻译成功后清空。
    @Published private(set) var translationError: String?

    private let audioSource: AudioSource
    private let asr: EnglishASR
    /// nil 表示没有可用的翻译，只显示英文字幕。
    private var translator: Translator?
    /// 设置后，translator 的结果先作为临时译文显示，refiner 的结果到达后替换它。
    private var refiner: CaptionRefiner?
    private let minChunkSamples: Int
    /// 窗口 RMS 低于此值视为静音，不送识别。Whisper 在静音上常输出 "you" 之类的幻觉文本。
    private let silenceRMSThreshold: Float
    /// 窗口满 minChunkSamples 后，在最后这段里找最安静的一帧切开，避免把单词切成两半。
    private let cutSearchSamples: Int
    private let cutFrameSamples: Int

    private(set) var pumpTask: Task<Void, Never>?
    private(set) var refineTasks: [UUID: Task<Void, Never>] = [:]

    init(
        audioSource: AudioSource,
        asr: EnglishASR,
        translator: Translator?,
        refiner: CaptionRefiner? = nil,
        minChunkDuration: TimeInterval = 3,
        sampleRate: Double = 16_000,
        silenceRMSThreshold: Float = 0.005,
        cutSearchDuration: TimeInterval = 1
    ) {
        self.audioSource = audioSource
        self.asr = asr
        self.translator = translator
        self.refiner = refiner
        self.minChunkSamples = Int(minChunkDuration * sampleRate)
        self.silenceRMSThreshold = silenceRMSThreshold
        self.cutSearchSamples = Int(cutSearchDuration * sampleRate)
        self.cutFrameSamples = Int(0.1 * sampleRate)
    }

    /// 会话中途更换翻译方式（例如本地资源下载完成后），只影响之后的语音。
    func updateTranslation(translator: Translator?, refiner: CaptionRefiner?) {
        self.translator = translator
        self.refiner = refiner
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
            let cut = cutIndex(in: buffer)
            let samples = Array(buffer[..<cut])
            buffer.removeFirst(cut)
            await transcribeAndTranslate(samples)
        }
    }

    /// 固定每 3 秒切一刀会把 "GitHub" 切成 "Git" 和 "Hub"，后半段常识别不出来。
    /// 改为切在最后 cutSearchSamples 里能量最低的一帧中间，切点之后的音频留给下一个窗口。
    private func cutIndex(in buffer: [Float]) -> Int {
        let frame = cutFrameSamples
        let lower = max(frame, buffer.count - cutSearchSamples)
        guard frame > 0, lower + frame <= buffer.count else { return buffer.count }
        var best = buffer.count
        var bestEnergy = Float.infinity
        var start = lower
        while start + frame <= buffer.count {
            let energy = buffer[start..<(start + frame)].reduce(0) { $0 + $1 * $1 }
            // 能量相同时取靠后的一帧，连续语音中窗口不会比设定长度短太多。
            if energy <= bestEnergy {
                bestEnergy = energy
                best = start + frame / 2
            }
            start += max(1, frame / 2)
        }
        return best
    }

    private func transcribeAndTranslate(_ samples: [Float]) async {
        guard rms(samples) >= silenceRMSThreshold else { return }
        let english: String
        do {
            english = try await asr.transcribe(samples: samples)
        } catch {
            await fail(error)
            return
        }
        guard !english.isEmpty, !isNonSpeechTranscript(english) else { return }

        let caption = Caption(id: UUID(), english: english, chinese: nil, isProvisional: true, createdAt: .now)
        captions.append(caption)

        guard let translator else {
            markEnglishOnly(id: caption.id)
            return
        }
        guard let refiner else {
            do {
                let chinese = try await translator.translate(english)
                translationError = nil
                updateCaption(id: caption.id, chinese: chinese, isProvisional: false)
            } catch {
                translationError = error.localizedDescription
                markEnglishOnly(id: caption.id)
            }
            return
        }
        setRefinement(id: caption.id, .refining)
        let draft = try? await translator.translate(english)
        if let draft {
            updateCaption(id: caption.id, chinese: draft, isProvisional: true, refinement: .refining)
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
    }

    private func finishRefinement(id: UUID, result: Result<String, Error>) {
        refineTasks[id] = nil
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let chinese):
            translationError = nil
            updateCaption(id: id, chinese: chinese, isProvisional: false, refinement: .refined)
        case .failure(let error):
            // 字幕里只显示“精修失败”，具体原因写进系统日志以便排查。
            logger.error("LLM refinement failed: \(String(describing: error), privacy: .public)")
            // 保留临时译文；两种翻译都没有结果时只保留英文，会话继续。
            if let draft = captions.first(where: { $0.id == id })?.chinese {
                updateCaption(id: id, chinese: draft, isProvisional: false, refinement: .failed)
            } else {
                translationError = error.localizedDescription
                setRefinement(id: id, .failed)
                markEnglishOnly(id: id)
            }
        }
    }

    private func markEnglishOnly(id: UUID) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        captions[index].isProvisional = false
    }

    private func setRefinement(id: UUID, _ refinement: Caption.Refinement) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        captions[index].refinement = refinement
    }

    private func cancelRefinements() {
        refineTasks.values.forEach { $0.cancel() }
        refineTasks.removeAll()
    }

    private func updateCaption(id: UUID, chinese: String, isProvisional: Bool, refinement: Caption.Refinement? = nil) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        let existing = captions[index]
        captions[index] = Caption(
            id: id,
            english: existing.english,
            chinese: chinese,
            isProvisional: isProvisional,
            createdAt: existing.createdAt,
            refinement: refinement
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

func rms(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
}
