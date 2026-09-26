import AVFoundation
import Speech

enum AppleSpeechError: LocalizedError {
    case unavailable
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unavailable: return "这台 Mac 不支持系统英文语音识别，请在“翻译设置”中改用 Whisper。"
        case .unsupportedFormat: return "无法把音频转换成系统语音识别需要的格式。"
        }
    }
}

/// macOS 26 起的系统语音识别（SpeechAnalyzer）。识别模型由系统下载和管理，App 不自带模型文件。
@available(macOS 26, *)
struct AppleSpeechEnglishASR: EnglishASR {
    private let locale: Locale
    private let analyzerFormat: AVAudioFormat

    static func load() async throws -> AppleSpeechEnglishASR {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        else { throw AppleSpeechError.unavailable }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        // 第一次使用时由系统下载英文识别资源，之后直接使用已安装的资源。
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechError.unsupportedFormat
        }
        return AppleSpeechEnglishASR(locale: locale, analyzerFormat: format)
    }

    /// 每个窗口单独分析一次，接口与 Whisper 一致，切窗逻辑不用改。
    func transcribe(samples: [Float]) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        let (input, builder) = AsyncStream<AnalyzerInput>.makeStream()
        builder.yield(AnalyzerInput(buffer: try buffer(from: samples)))
        builder.finish()
        do {
            _ = try await analyzer.analyzeSequence(input)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw error
        }
        return normalizeEnglishTranscript(try await collector.value)
    }

    private func buffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        let source = AudioResampler.targetFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw AppleSpeechError.unsupportedFormat
        }
        input.frameLength = input.frameCapacity
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        if analyzerFormat == source { return input }

        guard let converter = AVAudioConverter(from: source, to: analyzerFormat),
              let output = AVAudioPCMBuffer(
                  pcmFormat: analyzerFormat,
                  frameCapacity: AVAudioFrameCount(Double(samples.count) * analyzerFormat.sampleRate / source.sampleRate) + 1
              )
        else { throw AppleSpeechError.unsupportedFormat }
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }
        return output
    }
}
