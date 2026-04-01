import AppKit
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let audioRecorder = AudioRecorder()
    private let speechRecognizer = SpeechRecognizer()
    private let textInjector = TextInjector()
    private let llmClient = LLMClient()
    private let capsulePanel = CapsulePanel()
    private let settingsWindowController = SettingsWindowController()

    private var currentTranscription = ""
    private var isRecording = false

    // Language options
    private struct LanguageOption {
        let name: String
        let locale: String
    }

    private let languages: [LanguageOption] = [
        LanguageOption(name: "English", locale: "en-US"),
        LanguageOption(name: "简体中文", locale: "zh-CN"),
        LanguageOption(name: "繁體中文", locale: "zh-TW"),
        LanguageOption(name: "日本語", locale: "ja-JP"),
        LanguageOption(name: "한국어", locale: "ko-KR"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        Permissions.requestAll()
        setupStatusItem()
        setupKeyMonitor()
        setupAudioPipeline()
    }

    // MARK: - Status Bar Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Language submenu
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        let currentLocale = Settings.shared.language
        for lang in languages {
            let item = NSMenuItem(title: lang.name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.locale
            item.state = (lang.locale == currentLocale) ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // LLM Refinement submenu
        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()

        let enableItem = NSMenuItem(
            title: Settings.shared.llmEnabled ? "Enabled" : "Disabled",
            action: #selector(toggleLLM(_:)),
            keyEquivalent: ""
        )
        enableItem.target = self
        enableItem.state = Settings.shared.llmEnabled ? .on : .off
        llmMenu.addItem(enableItem)

        llmMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Voice Input", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let locale = sender.representedObject as? String else { return }
        Settings.shared.language = locale
        rebuildMenu()
    }

    @objc private func toggleLLM(_ sender: NSMenuItem) {
        Settings.shared.llmEnabled = !Settings.shared.llmEnabled
        rebuildMenu()
    }

    @objc private func openSettings() {
        settingsWindowController.showWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Key Monitor

    private func setupKeyMonitor() {
        keyMonitor.onRecordingStart = { [weak self] in
            DispatchQueue.main.async {
                self?.startRecording()
            }
        }
        keyMonitor.onRecordingStop = { [weak self] in
            DispatchQueue.main.async {
                self?.stopRecording()
            }
        }
        keyMonitor.start()
    }

    // MARK: - Audio Pipeline

    private func setupAudioPipeline() {
        audioRecorder.onAudioLevel = { [weak self] level in
            self?.capsulePanel.waveformView.setLevel(level)
        }

        audioRecorder.onBuffer = { [weak self] buffer in
            self?.speechRecognizer.appendBuffer(buffer)
        }

        speechRecognizer.onPartialResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.currentTranscription = text
                self?.capsulePanel.updateText(text)
            }
        }

        speechRecognizer.onFinalResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.currentTranscription = text
                self?.capsulePanel.updateText(text)
            }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        currentTranscription = ""

        // Start speech recognizer with selected locale
        let locale = Locale(identifier: Settings.shared.language)
        speechRecognizer.start(locale: locale)

        // Start audio
        do {
            try audioRecorder.start()
        } catch {
            print("Failed to start audio recorder: \(error)")
            isRecording = false
            return
        }

        // Show capsule
        capsulePanel.showRecording()

        // Update status icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.badge.plus", accessibilityDescription: "Recording")
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        // Stop audio & recognition
        audioRecorder.stop()
        speechRecognizer.stop()

        // Reset status icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
        }

        let text = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            capsulePanel.dismiss()
            return
        }

        // LLM refinement if enabled
        if Settings.shared.llmEnabled && Settings.shared.isLLMConfigured {
            capsulePanel.showRefining()

            llmClient.refine(text: text) { [weak self] result in
                DispatchQueue.main.async {
                    let finalText: String
                    switch result {
                    case .success(let refined):
                        finalText = refined
                    case .failure(let error):
                        print("LLM refinement failed: \(error). Using original text.")
                        finalText = text
                    }

                    self?.capsulePanel.dismiss()
                    // Small delay to let the capsule dismiss animation start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self?.textInjector.inject(text: finalText)
                    }
                }
            }
        } else {
            capsulePanel.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.textInjector.inject(text: text)
            }
        }
    }
}
