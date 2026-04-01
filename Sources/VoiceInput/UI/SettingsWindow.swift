import AppKit
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let whisperModelPathField = NSTextField()
    private let baseURLField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let testButton = NSButton(title: "Test", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let padding: CGFloat = 20
        let fieldHeight: CGFloat = 24
        let labelWidth: CGFloat = 100
        let fieldWidth: CGFloat = 340

        // --- Whisper section ---
        let whisperHeader = NSTextField(labelWithString: "Whisper Model")
        whisperHeader.frame = NSRect(x: padding, y: 300, width: fieldWidth, height: fieldHeight)
        whisperHeader.font = .boldSystemFont(ofSize: 13)
        contentView.addSubview(whisperHeader)

        let pathLabel = NSTextField(labelWithString: "Model Path:")
        pathLabel.frame = NSRect(x: padding, y: 270, width: labelWidth, height: fieldHeight)
        pathLabel.alignment = .right
        contentView.addSubview(pathLabel)

        whisperModelPathField.frame = NSRect(x: padding + labelWidth + 8, y: 270, width: fieldWidth - labelWidth - 78, height: fieldHeight)
        whisperModelPathField.placeholderString = "path/to/ggml-base.en.bin"
        contentView.addSubview(whisperModelPathField)

        let browseButton = NSButton(title: "Browse", target: self, action: #selector(browseModel))
        browseButton.bezelStyle = .rounded
        browseButton.frame = NSRect(x: fieldWidth - 40, y: 268, width: 70, height: 28)
        contentView.addSubview(browseButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: padding, y: 252, width: fieldWidth, height: 1)
        contentView.addSubview(separator)

        // --- LLM Refinement section ---
        let llmHeader = NSTextField(labelWithString: "LLM Refinement")
        llmHeader.frame = NSRect(x: padding, y: 224, width: fieldWidth, height: fieldHeight)
        llmHeader.font = .boldSystemFont(ofSize: 13)
        contentView.addSubview(llmHeader)

        // API Base URL
        let urlLabel = NSTextField(labelWithString: "API Base URL:")
        urlLabel.frame = NSRect(x: padding, y: 194, width: labelWidth, height: fieldHeight)
        urlLabel.alignment = .right
        contentView.addSubview(urlLabel)

        baseURLField.frame = NSRect(x: padding + labelWidth + 8, y: 194, width: fieldWidth - labelWidth - 8, height: fieldHeight)
        baseURLField.placeholderString = "https://api.openai.com"
        contentView.addSubview(baseURLField)

        // API Key
        let keyLabel = NSTextField(labelWithString: "API Key:")
        keyLabel.frame = NSRect(x: padding, y: 160, width: labelWidth, height: fieldHeight)
        keyLabel.alignment = .right
        contentView.addSubview(keyLabel)

        apiKeyField.frame = NSRect(x: padding + labelWidth + 8, y: 160, width: fieldWidth - labelWidth - 8, height: fieldHeight)
        apiKeyField.placeholderString = "sk-..."
        contentView.addSubview(apiKeyField)

        // Model
        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.frame = NSRect(x: padding, y: 126, width: labelWidth, height: fieldHeight)
        modelLabel.alignment = .right
        contentView.addSubview(modelLabel)

        modelField.frame = NSRect(x: padding + labelWidth + 8, y: 126, width: fieldWidth - labelWidth - 8, height: fieldHeight)
        modelField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelField)

        // Status label
        statusLabel.frame = NSRect(x: padding, y: 90, width: fieldWidth, height: fieldHeight)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        contentView.addSubview(statusLabel)

        // Buttons
        testButton.frame = NSRect(x: fieldWidth - 140, y: 40, width: 80, height: 32)
        testButton.bezelStyle = .rounded
        testButton.target = self
        testButton.action = #selector(testConnection)
        contentView.addSubview(testButton)

        saveButton.frame = NSRect(x: fieldWidth - 50, y: 40, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        contentView.addSubview(saveButton)
    }

    private func loadSettings() {
        let settings = Settings.shared
        whisperModelPathField.stringValue = settings.whisperModelPath
        baseURLField.stringValue = settings.llmBaseURL
        apiKeyField.stringValue = settings.llmAPIKey
        modelField.stringValue = settings.llmModel
    }

    @objc private func browseModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.message = "Select a whisper.cpp GGML model file (.bin)"
        if panel.runModal() == .OK, let url = panel.url {
            whisperModelPathField.stringValue = url.path
        }
    }

    @objc private func testConnection() {
        let baseURL = baseURLField.stringValue
        let apiKey = apiKeyField.stringValue
        let model = modelField.stringValue

        guard !baseURL.isEmpty, !apiKey.isEmpty, !model.isEmpty else {
            statusLabel.stringValue = "Please fill in all fields."
            statusLabel.textColor = .systemOrange
            return
        }

        statusLabel.stringValue = "Testing..."
        statusLabel.textColor = .secondaryLabelColor
        testButton.isEnabled = false

        LLMClient().testConnection(baseURL: baseURL, apiKey: apiKey, model: model) { [weak self] result in
            DispatchQueue.main.async {
                self?.testButton.isEnabled = true
                switch result {
                case .success(let msg):
                    self?.statusLabel.stringValue = msg
                    self?.statusLabel.textColor = .systemGreen
                case .failure(let error):
                    self?.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    self?.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    @objc private func saveSettings() {
        let settings = Settings.shared
        settings.whisperModelPath = whisperModelPathField.stringValue
        settings.llmBaseURL = baseURLField.stringValue
        settings.llmAPIKey = apiKeyField.stringValue
        settings.llmModel = modelField.stringValue

        statusLabel.stringValue = "Settings saved."
        statusLabel.textColor = .systemGreen

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.window?.close()
        }
    }

    func showWindow() {
        loadSettings()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
