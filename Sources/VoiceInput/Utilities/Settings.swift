import Foundation

final class Settings {
    static let shared = Settings()

    static var configFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/voice-input/config.json")
    }

    private struct Config: Codable {
        var language: String = "en-US"
        var sttBackend: String = "apple"
        var whisperModelPath: String = ""
        var llmEnabled: Bool = false
        var llmBaseURL: String = ""
        var llmAPIKey: String = ""
        var llmModel: String = ""
    }

    private var config = Config()

    private init() {
        load()
    }

    func load() {
        let url = Self.configFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            config = Config()
            save()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            config = try decoder.decode(Config.self, from: data)
        } catch {
            NSLog("[Settings] Failed to load config: %@", error.localizedDescription)
            config = Config()
        }
    }

    func save() {
        let url = Self.configFileURL
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[Settings] Failed to save config: %@", error.localizedDescription)
        }
    }

    var language: String {
        get { config.language }
        set { config.language = newValue; save() }
    }

    var llmEnabled: Bool {
        get { config.llmEnabled }
        set { config.llmEnabled = newValue; save() }
    }

    var llmBaseURL: String {
        get { config.llmBaseURL }
        set { config.llmBaseURL = newValue; save() }
    }

    var llmAPIKey: String {
        get { config.llmAPIKey }
        set { config.llmAPIKey = newValue; save() }
    }

    var llmModel: String {
        get { config.llmModel }
        set { config.llmModel = newValue; save() }
    }

    var isLLMConfigured: Bool {
        !llmBaseURL.isEmpty && !llmAPIKey.isEmpty && !llmModel.isEmpty
    }

    var sttBackend: String {
        get { config.sttBackend }
        set { config.sttBackend = newValue; save() }
    }

    var whisperModelPath: String {
        get {
            let path = config.whisperModelPath
            if path.isEmpty {
                return defaultWhisperModelPath
            }

            if path == oldBundledDefaultModelPath {
                config.whisperModelPath = defaultWhisperModelPath
                save()
                return defaultWhisperModelPath
            }

            return path
        }
        set { config.whisperModelPath = newValue; save() }
    }

    private var defaultWhisperModelPath: String {
        Bundle.main.resourcePath.map { $0 + "/ggml-large-v3-turbo-q8_0.bin" } ?? ""
    }

    private var oldBundledDefaultModelPath: String {
        Bundle.main.resourcePath.map { $0 + "/ggml-base.en.bin" } ?? ""
    }
}
