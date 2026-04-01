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
    private var currentLanguage: String?

    func start(locale: Locale) {
        currentLanguage = WhisperBridge.whisperLanguage(from: locale)
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
            let text = bridge.transcribe(samples: samples, language: self.currentLanguage)
            NSLog("[WhisperRecognizer] Final result: %@", text)

            DispatchQueue.main.async {
                self.onFinalResult?(text)
                self.whisperBridge = nil
            }
        }
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
        let text = bridge.transcribe(samples: samples, language: currentLanguage)
        isInferring = false

        if !text.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onPartialResult?(text)
            }
        }
    }
}
