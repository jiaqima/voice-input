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
}
