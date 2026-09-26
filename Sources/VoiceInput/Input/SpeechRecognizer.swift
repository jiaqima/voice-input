import Speech

final class SpeechRecognizer: SpeechRecognizerProtocol {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionID = 0

    func start(language: RecognitionLanguage) {
        sessionID += 1
        let session = sessionID
        let locale = language.fallbackLocale
        if case .autoChineseEnglish = language {
            NSLog("[SpeechRecognizer] Auto (中/英) mode requires the Whisper backend; falling back to %@", locale.identifier)
        }
        recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("Speech recognizer not available for locale: \(locale.identifier)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 15, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.sessionID == session else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.onFinalResult?(text)
                } else {
                    self.onPartialResult?(text)
                }
            }

            if let error = error {
                self.onError?(error)
            }
        }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stop() {
        // finish() lets the task deliver its final result; cancel() would drop it.
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil
    }
}
