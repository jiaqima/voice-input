import Foundation

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let language = "selectedLanguage"
        static let llmEnabled = "llmEnabled"
        static let llmBaseURL = "llmBaseURL"
        static let llmAPIKey = "llmAPIKey"
        static let llmModel = "llmModel"
        static let sttBackend = "sttBackend"
        static let whisperModelPath = "whisperModelPath"
    }

    var language: String {
        get { defaults.string(forKey: Keys.language) ?? "en-US" }
        set { defaults.set(newValue, forKey: Keys.language) }
    }

    var llmEnabled: Bool {
        get { defaults.bool(forKey: Keys.llmEnabled) }
        set { defaults.set(newValue, forKey: Keys.llmEnabled) }
    }

    var llmBaseURL: String {
        get { defaults.string(forKey: Keys.llmBaseURL) ?? "" }
        set { defaults.set(newValue, forKey: Keys.llmBaseURL) }
    }

    var llmAPIKey: String {
        get { defaults.string(forKey: Keys.llmAPIKey) ?? "" }
        set { defaults.set(newValue, forKey: Keys.llmAPIKey) }
    }

    var llmModel: String {
        get { defaults.string(forKey: Keys.llmModel) ?? "" }
        set { defaults.set(newValue, forKey: Keys.llmModel) }
    }

    var isLLMConfigured: Bool {
        !llmBaseURL.isEmpty && !llmAPIKey.isEmpty && !llmModel.isEmpty
    }

    // Speech-to-text backend: "apple" or "whisper"
    var sttBackend: String {
        get { defaults.string(forKey: Keys.sttBackend) ?? "apple" }
        set { defaults.set(newValue, forKey: Keys.sttBackend) }
    }

    var whisperModelPath: String {
        get { defaults.string(forKey: Keys.whisperModelPath) ?? defaultWhisperModelPath }
        set { defaults.set(newValue, forKey: Keys.whisperModelPath) }
    }

    private var defaultWhisperModelPath: String {
        Bundle.main.resourcePath.map { $0 + "/ggml-base.en.bin" } ?? ""
    }
}
