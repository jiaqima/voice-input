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

    private var threadCount: Int32 {
        Int32(min(ProcessInfo.processInfo.activeProcessorCount, 8))
    }

    struct LanguageProbabilities {
        let zh: Float
        let en: Float
        let topLanguage: String
    }

    /// Run whisper's language detector on the first 30s window of the samples.
    /// Returns nil if detection fails.
    func detectLanguage(samples: [Float]) -> LanguageProbabilities? {
        guard let ctx = ctx, !samples.isEmpty else { return nil }

        let melResult = samples.withUnsafeBufferPointer { samplesPtr in
            whisper_pcm_to_mel(ctx, samplesPtr.baseAddress, Int32(samples.count), threadCount)
        }
        guard melResult == 0 else {
            NSLog("[WhisperBridge] whisper_pcm_to_mel failed: %d", melResult)
            return nil
        }

        var probs = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let topID = probs.withUnsafeMutableBufferPointer { probsPtr in
            whisper_lang_auto_detect(ctx, 0, threadCount, probsPtr.baseAddress)
        }
        guard topID >= 0 else {
            NSLog("[WhisperBridge] language detection failed: %d", topID)
            return nil
        }

        let zhID = Int(whisper_lang_id("zh"))
        let enID = Int(whisper_lang_id("en"))
        let topLanguage = whisper_lang_str(topID).map { String(cString: $0) } ?? "?"
        return LanguageProbabilities(
            zh: zhID >= 0 ? probs[zhID] : 0,
            en: enID >= 0 ? probs[enID] : 0,
            topLanguage: topLanguage
        )
    }

    /// Transcribe Float32 PCM samples at 16kHz mono.
    /// Returns the concatenated text from all segments.
    /// - language: whisper language code, or nil for auto-detect.
    /// - initialPrompt: optional text that steers vocabulary and script (e.g. Simplified Chinese).
    func transcribe(samples: [Float], language: String?, initialPrompt: String? = nil) -> String {
        guard let ctx = ctx else { return "" }
        guard !samples.isEmpty else { return "" }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = threadCount
        params.no_timestamps = true
        params.single_segment = false

        // C strings must outlive the whisper_full call.
        var langCString: [CChar] = language.map { Array($0.utf8CString) } ?? []
        var promptCString: [CChar] = initialPrompt.map { Array($0.utf8CString) } ?? []

        let result: Int32 = samples.withUnsafeBufferPointer { samplesPtr in
            langCString.withUnsafeMutableBufferPointer { langPtr in
                promptCString.withUnsafeMutableBufferPointer { promptPtr in
                    params.language = langPtr.isEmpty ? nil : UnsafePointer(langPtr.baseAddress)
                    params.initial_prompt = promptPtr.isEmpty ? nil : UnsafePointer(promptPtr.baseAddress)
                    return whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samples.count))
                }
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
