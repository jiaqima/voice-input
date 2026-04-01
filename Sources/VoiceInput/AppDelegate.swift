import AppKit
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let audioRecorder = AudioRecorder()
    private var speechRecognizer: SpeechRecognizerProtocol = SpeechRecognizer()
    private let textInjector = TextInjector()
    private let llmClient = LLMClient()
    private let capsulePanel = CapsulePanel()


    private var currentTranscription = ""
    private var isRecording = false
    private var isRebuildingMenu = false
    private var activeSubmissionID: UInt64?
    private var nextSubmissionID: UInt64 = 0
    private var refinementTimeoutWorkItem: DispatchWorkItem?
    private var pendingRefinementRequest: LLMClient.RefinementRequest?

    private static let refinementTimeout: TimeInterval = 2.0

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
        speechRecognizer = createSpeechRecognizer()
        setupStatusItem()
        setupKeyMonitor()
        setupAudioPipeline()
    }

    private func createSpeechRecognizer() -> SpeechRecognizerProtocol {
        if Settings.shared.sttBackend == "whisper" {
            return WhisperSpeechRecognizer()
        }
        return SpeechRecognizer()
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
        isRebuildingMenu = true
        defer { isRebuildingMenu = false }
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

        // Speech backend submenu
        let backendItem = NSMenuItem(title: "Speech Backend", action: nil, keyEquivalent: "")
        let backendMenu = NSMenu()
        let currentBackend = Settings.shared.sttBackend

        let appleItem = NSMenuItem(title: "Apple Speech", action: #selector(selectBackend(_:)), keyEquivalent: "")
        appleItem.target = self
        appleItem.representedObject = "apple"
        appleItem.state = currentBackend == "apple" ? .on : .off
        backendMenu.addItem(appleItem)

        let whisperItem = NSMenuItem(title: "Whisper (Local)", action: #selector(selectBackend(_:)), keyEquivalent: "")
        whisperItem.target = self
        whisperItem.representedObject = "whisper"
        whisperItem.state = currentBackend == "whisper" ? .on : .off
        backendMenu.addItem(whisperItem)

        backendItem.submenu = backendMenu
        menu.addItem(backendItem)

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

        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Voice Input", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard !isRebuildingMenu else { return }
        Settings.shared.load()
        rebuildMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let locale = sender.representedObject as? String else { return }
        Settings.shared.language = locale
        rebuildMenu()
    }

    @objc private func selectBackend(_ sender: NSMenuItem) {
        guard let backend = sender.representedObject as? String else { return }
        guard !isRecording else { return }
        Settings.shared.sttBackend = backend
        speechRecognizer = createSpeechRecognizer()
        setupAudioPipeline()
        rebuildMenu()
    }

    @objc private func toggleLLM(_ sender: NSMenuItem) {
        Settings.shared.llmEnabled = !Settings.shared.llmEnabled
        rebuildMenu()
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(Settings.configFileURL)
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

        speechRecognizer.onError = { error in
            NSLog("[VoiceInput] speech error: %@", error.localizedDescription)
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isRecording else { return }
        cancelPendingRefinement(reason: "starting a new recording")
        activeSubmissionID = nil
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
        let submissionID = makeSubmissionID()
        activeSubmissionID = submissionID

        // Stop audio & recognition
        audioRecorder.stop()
        speechRecognizer.stop()

        // Reset status icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
        }

        let targetContext = textInjector.captureTargetContext()
        let text = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            activeSubmissionID = nil
            capsulePanel.dismiss()
            return
        }

        // LLM refinement if enabled
        if Settings.shared.llmEnabled && Settings.shared.isLLMConfigured {
            startRefinement(for: text, targetContext: targetContext, submissionID: submissionID)
        } else {
            injectTranscription(text, targetContext: targetContext, submissionID: submissionID)
        }
    }

    private func startRefinement(
        for originalText: String,
        targetContext: TextInjector.TargetContext?,
        submissionID: UInt64
    ) {
        let startedAt = Date()
        NSLog("[VoiceInput] submission \(submissionID) refinement started (\(originalText.count) chars)")
        capsulePanel.showRefining()

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.handleRefinementTimeout(
                originalText: originalText,
                targetContext: targetContext,
                submissionID: submissionID,
                startedAt: startedAt
            )
        }
        refinementTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refinementTimeout, execute: timeoutWorkItem)

        pendingRefinementRequest = llmClient.refine(text: originalText) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleRefinementResult(
                    result,
                    originalText: originalText,
                    targetContext: targetContext,
                    submissionID: submissionID,
                    startedAt: startedAt
                )
            }
        }
    }

    private func handleRefinementResult(
        _ result: Result<String, Error>,
        originalText: String,
        targetContext: TextInjector.TargetContext?,
        submissionID: UInt64,
        startedAt: Date
    ) {
        guard isCurrentSubmission(submissionID) else {
            NSLog("[VoiceInput] submission \(submissionID) refinement result ignored because a newer submission is active")
            return
        }

        refinementTimeoutWorkItem?.cancel()
        refinementTimeoutWorkItem = nil
        pendingRefinementRequest = nil

        let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
        switch result {
        case .success(let refinedText):
            NSLog("[VoiceInput] submission \(submissionID) refinement succeeded in \(elapsed)s")
            injectTranscription(refinedText, targetContext: targetContext, submissionID: submissionID)
        case .failure(let error):
            NSLog("[VoiceInput] submission \(submissionID) refinement failed in \(elapsed)s: \(error.localizedDescription)")
            NSLog("[VoiceInput] submission \(submissionID) falling back to original transcript")
            injectTranscription(originalText, targetContext: targetContext, submissionID: submissionID)
        }
    }

    private func handleRefinementTimeout(
        originalText: String,
        targetContext: TextInjector.TargetContext?,
        submissionID: UInt64,
        startedAt: Date
    ) {
        guard isCurrentSubmission(submissionID) else { return }

        let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
        NSLog("[VoiceInput] submission \(submissionID) refinement timed out after \(elapsed)s")
        NSLog("[VoiceInput] submission \(submissionID) falling back to original transcript")
        cancelPendingRefinement(reason: "submission \(submissionID) timed out")
        injectTranscription(originalText, targetContext: targetContext, submissionID: submissionID)
    }

    private func injectTranscription(
        _ text: String,
        targetContext: TextInjector.TargetContext?,
        submissionID: UInt64
    ) {
        guard isCurrentSubmission(submissionID) else {
            NSLog("[VoiceInput] submission \(submissionID) injection skipped because a newer submission is active")
            return
        }

        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            NSLog("[VoiceInput] submission \(submissionID) injection skipped because the transcript is empty")
            activeSubmissionID = nil
            capsulePanel.dismiss()
            return
        }

        cancelPendingRefinement(reason: "submission \(submissionID) is ready to inject")
        capsulePanel.dismiss()

        // Wait for dismiss animation (220ms) to fully complete plus margin for the target app to regain focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            guard self.isCurrentSubmission(submissionID) else {
                NSLog("[VoiceInput] submission \(submissionID) delayed injection ignored because a newer submission is active")
                return
            }

            NSLog("[VoiceInput] submission \(submissionID) injecting \(finalText.count) chars")
            self.textInjector.inject(text: finalText, targetContext: targetContext) { result in
                DispatchQueue.main.async {
                    guard self.isCurrentSubmission(submissionID) else {
                        NSLog("[VoiceInput] submission \(submissionID) injection result ignored because a newer submission is active")
                        return
                    }

                    self.activeSubmissionID = nil
                    self.handleInjectionResult(result)
                }
            }
        }
    }

    private func cancelPendingRefinement(reason: String) {
        if pendingRefinementRequest != nil {
            NSLog("[VoiceInput] canceling pending refinement: \(reason)")
        }
        pendingRefinementRequest?.cancel()
        pendingRefinementRequest = nil
        refinementTimeoutWorkItem?.cancel()
        refinementTimeoutWorkItem = nil
    }

    private func isCurrentSubmission(_ submissionID: UInt64) -> Bool {
        activeSubmissionID == submissionID
    }

    private func makeSubmissionID() -> UInt64 {
        nextSubmissionID += 1
        return nextSubmissionID
    }

    private func handleInjectionResult(_ result: TextInjector.InjectionResult) {
        switch result {
        case .accessibilitySuccess, .typingSimulationSuccess:
            break

        case .automaticPastePosted:
            break

        case .manualPasteRequired:
            capsulePanel.showStatus("Text copied. Press Cmd+V to paste.")
        }
    }
}
