import AVFoundation

final class WhisperSpeechRecognizer: SpeechRecognizerProtocol {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var whisperBridge: WhisperBridge?
    private var accumulatedSamples: [Float] = []
    private let sampleLock = NSLock()

    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    private let inferenceQueue = DispatchQueue(label: "whisper.inference", qos: .userInitiated)
    private var partialTimer: DispatchSourceTimer?
    private var isInferring = false
    private var currentMode: RecognitionLanguage = .locale(Locale(identifier: "en-US"))

    /// Language chosen for `.autoChineseEnglish`, cached once enough audio has been heard
    /// so the language cannot flip mid-recording and later passes skip detection.
    private var resolvedAutoLanguage: String?

    /// Minimum audio before the auto zh/en decision is locked in.
    private static let autoLanguageLockSamples = 3 * 16000
    /// Prefer zh whenever its probability is at least this, so Chinese with English terms stays zh.
    private static let zhBiasThreshold: Float = 0.2

    private static let simplifiedChineseMixedPrompt =
        "以下是普通话的句子，其中夹杂一些英文术语，比如 Python、API、GitHub、Docker。"

    func start(language: RecognitionLanguage) {
        currentMode = language
        resolvedAutoLanguage = nil
        sampleLock.lock()
        accumulatedSamples = []
        sampleLock.unlock()
        converter = nil

        let modelPath = Settings.shared.whisperModelPath
        do {
            whisperBridge = try WhisperBridge(modelPath: modelPath)
        } catch {
            NSLog("[WhisperRecognizer] Failed to load model: %@", error.localizedDescription)
            onError?(error)
            return
        }

        startPartialTimer()
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard whisperBridge != nil else { return }

        // Lazily create converter from input format to 16kHz mono
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            if converter == nil {
                NSLog("[WhisperRecognizer] Failed to create audio converter from %@ to %@",
                      buffer.format.description, targetFormat.description)
                return
            }
        }

        // Resample to 16kHz mono
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return
        }

        var consumed = false
        var convError: NSError?
        converter?.convert(to: outputBuffer, error: &convError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let convError = convError {
            NSLog("[WhisperRecognizer] Conversion error: %@", convError.localizedDescription)
            return
        }

        guard let channelData = outputBuffer.floatChannelData, outputBuffer.frameLength > 0 else {
            return
        }

        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))

        sampleLock.lock()
        accumulatedSamples.append(contentsOf: samples)
        sampleLock.unlock()
    }

    func stop() {
        partialTimer?.cancel()
        partialTimer = nil

        sampleLock.lock()
        let samples = accumulatedSamples
        sampleLock.unlock()

        inferenceQueue.async { [weak self] in
            guard let self = self, let bridge = self.whisperBridge else {
                DispatchQueue.main.async { self?.onFinalResult?("") }
                return
            }

            NSLog("[WhisperRecognizer] Final inference on %d samples (%.1fs)", samples.count, Double(samples.count) / 16000.0)
            let settings = self.resolveTranscriptionSettings(for: samples, bridge: bridge)
            let text = bridge.transcribe(samples: samples, language: settings.language, initialPrompt: settings.prompt)
            NSLog("[WhisperRecognizer] Final result: %@", text)

            DispatchQueue.main.async {
                self.onFinalResult?(text)
                self.whisperBridge = nil
            }
        }
    }

    // MARK: - Language Resolution

    /// Decide the whisper language and steering prompt for this pass. Runs on `inferenceQueue`.
    private func resolveTranscriptionSettings(
        for samples: [Float],
        bridge: WhisperBridge
    ) -> (language: String?, prompt: String?) {
        switch currentMode {
        case .locale(let locale):
            return (WhisperBridge.whisperLanguage(from: locale), nil)

        case .autoChineseEnglish:
            let language: String
            if let cached = resolvedAutoLanguage {
                language = cached
            } else {
                language = detectAutoLanguage(for: samples, bridge: bridge)
                if samples.count >= Self.autoLanguageLockSamples {
                    resolvedAutoLanguage = language
                    NSLog("[WhisperRecognizer] Auto language locked to %@", language)
                }
            }
            let prompt = language == "zh" ? Self.simplifiedChineseMixedPrompt : nil
            return (language, prompt)
        }
    }

    /// Biased zh/en decision: zh unless the audio is clearly English.
    private func detectAutoLanguage(for samples: [Float], bridge: WhisperBridge) -> String {
        guard let probs = bridge.detectLanguage(samples: samples) else {
            return "zh"
        }
        let language = (probs.zh >= probs.en || probs.zh >= Self.zhBiasThreshold) ? "zh" : "en"
        NSLog("[WhisperRecognizer] Auto language: zh=%.3f en=%.3f top=%@ -> %@",
              probs.zh, probs.en, probs.topLanguage, language)
        return language
    }

    // MARK: - Partial Results

    private func startPartialTimer() {
        let timer = DispatchSource.makeTimerSource(queue: inferenceQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.runPartialInference()
        }
        timer.resume()
        partialTimer = timer
    }

    private func runPartialInference() {
        guard !isInferring else { return }
        guard let bridge = whisperBridge else { return }

        sampleLock.lock()
        let samples = accumulatedSamples
        sampleLock.unlock()

        // Need at least 0.5s of audio
        guard samples.count >= 8000 else { return }

        isInferring = true
        let settings = resolveTranscriptionSettings(for: samples, bridge: bridge)
        let text = bridge.transcribe(samples: samples, language: settings.language, initialPrompt: settings.prompt)
        isInferring = false

        if !text.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onPartialResult?(text)
            }
        }
    }
}
