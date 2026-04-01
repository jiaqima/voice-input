import AVFoundation

final class AudioRecorder {
    var onAudioLevel: ((Float) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let engine = AVAudioEngine()
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        onBuffer?(buffer)

        // Compute RMS level
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let data = channelData[0]

        var sum: Float = 0
        for i in 0..<frames {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(max(frames, 1)))
        // Convert to a 0-1 range (roughly)
        let level = min(rms * 5.0, 1.0)

        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(level)
        }
    }
}
