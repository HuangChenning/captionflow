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
    /// 窗口满 minChunkSamples 后，从它之前这段开始找停顿，在停顿处切开，避免把单词切成两半。
    private let cutSearchSamples: Int
    /// 一直没有停顿时，窗口达到这个长度才硬切。
    private let maxChunkSamples: Int
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
        cutSearchDuration: TimeInterval = 1,
        maxChunkDuration: TimeInterval = 6
    ) {
        self.audioSource = audioSource
        self.asr = asr
        self.translator = translator
        self.refiner = refiner
        self.minChunkSamples = Int(minChunkDuration * sampleRate)
        self.silenceRMSThreshold = silenceRMSThreshold
        self.cutSearchSamples = Int(cutSearchDuration * sampleRate)
        self.cutFrameSamples = Int(0.1 * sampleRate)
        self.maxChunkSamples = Int(maxChunkDuration * sampleRate)
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
            guard let cut = cutIndex(in: buffer) else { continue }
            let samples = Array(buffer[..<cut])
            buffer.removeFirst(cut)
            await transcribeAndTranslate(samples)
        }
    }

    /// 固定每 3 秒切一刀会把 "GitHub" 切成 "Git" 和 "Hub"，后半段常识别不出来；
    /// 只挑能量最低的位置切也不行，连续语音里能量最低处常在词中间（"pull request" 被切成 "pool re" 和 "quest"）。
    /// 所以只在真正的停顿处切：返回停顿中点；还没有停顿时返回 nil 继续收音频，达到 maxChunkSamples 才硬切。
    private func cutIndex(in buffer: [Float]) -> Int? {
        let frame = cutFrameSamples
        guard frame > 0 else { return buffer.count }
        // 帧 RMS 远低于整段语音的平均水平（或本身就是静音）才算停顿。
        let pauseRMS = max(silenceRMSThreshold, 0.1 * rms(buffer))
        var best: Int?
        var bestRMS = pauseRMS
        var start = max(frame, minChunkSamples - cutSearchSamples)
        while start + frame <= buffer.count {
            let frameRMS = rms(Array(buffer[start..<(start + frame)]))
            if frameRMS < bestRMS {
                bestRMS = frameRMS
                best = start + frame / 2
            }
            start += max(1, frame / 2)
        }
        if let best { return best }
        return buffer.count >= maxChunkSamples ? buffer.count : nil
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
