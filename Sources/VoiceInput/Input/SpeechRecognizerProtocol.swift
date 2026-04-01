import AVFoundation

protocol SpeechRecognizerProtocol: AnyObject {
    var onPartialResult: ((String) -> Void)? { get set }
    var onFinalResult: ((String) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func start(locale: Locale)
    func appendBuffer(_ buffer: AVAudioPCMBuffer)
    func stop()
}
