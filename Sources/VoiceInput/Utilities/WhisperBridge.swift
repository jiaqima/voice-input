import Foundation

final class WhisperBridge {
    private var ctx: OpaquePointer?

    enum WhisperError: Error, LocalizedError {
        case modelNotFound(String)
        case initFailed

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let path):
                return "Whisper model not found at \(path). Run 'make download-model' first."
            case .initFailed:
                return "Failed to initialize whisper context."
            }
        }
    }

    init(modelPath: String) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound(modelPath)
        }

        let params = whisper_context_default_params()
        ctx = whisper_init_from_file_with_params(modelPath, params)
        guard ctx != nil else {
            throw WhisperError.initFailed
        }
        NSLog("[WhisperBridge] Model loaded: %@", modelPath)
    }

    deinit {
        if let ctx = ctx {
            whisper_free(ctx)
        }
    }

    /// Transcribe Float32 PCM samples at 16kHz mono.
    /// Returns the concatenated text from all segments.
    func transcribe(samples: [Float], language: String?) -> String {
        guard let ctx = ctx else { return "" }
        guard !samples.isEmpty else { return "" }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(min(ProcessInfo.processInfo.activeProcessorCount, 8))
        params.no_timestamps = true
        params.single_segment = false

        // Set language (nil = auto-detect)
        var langCString: [CChar] = language.map { Array($0.utf8CString) } ?? []

        let result: Int32 = samples.withUnsafeBufferPointer { samplesPtr in
            langCString.withUnsafeMutableBufferPointer { langPtr in
                params.language = langPtr.isEmpty ? nil : UnsafePointer(langPtr.baseAddress)
                return whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samples.count))
            }
        }

        guard result == 0 else {
            NSLog("[WhisperBridge] whisper_full failed: %d", result)
            return ""
        }

        let nSegments = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<nSegments {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: cStr)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Map a Locale to a whisper language code.
    static func whisperLanguage(from locale: Locale) -> String? {
        let id = locale.identifier
        if id.hasPrefix("en") { return "en" }
        if id.hasPrefix("zh") { return "zh" }
        if id.hasPrefix("ja") { return "ja" }
        if id.hasPrefix("ko") { return "ko" }
        // Return nil for auto-detect
        return nil
    }
}
