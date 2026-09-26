import AppKit

final class KeyMonitor {
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?
    /// Fired once per recording when Shift is pressed while Fn is still held.
    var onEditRequested: (() -> Void)?

    // The first Fn press must be a short tap; the second press must be held to record.
    private enum State {
        case idle
        case firstPressDown
        case waitingForSecondPress
        case secondPressHolding
        case recording
    }

    private var monitor: Any?
    private var localMonitor: Any?
    private var state: State = .idle
    private var stateTimer: Timer?
    private var editRequestedThisRecording = false

    private static let doubleTapWindow: TimeInterval = 0.5
    private static let secondHoldThreshold: TimeInterval = 0.5

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            DispatchQueue.main.async {
                self?.handleFlagsChanged(flags)
            }
        }
        // Global monitors do not see events delivered to this app, so also watch locally
        // for when one of our own panels (e.g. the edit box) is the key window.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            DispatchQueue.main.async {
                self?.handleFlagsChanged(flags)
            }
            return event
        }
        if monitor == nil {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Access Required"
                alert.informativeText = "Voice Input needs Accessibility access to monitor the Fn key. Please grant access in System Settings > Privacy & Security > Accessibility, then restart the app."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        monitor = nil
        localMonitor = nil
        resetState()
    }

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let fnActive = flags.contains(.function)
        if state == .recording, fnActive, flags.contains(.shift), !editRequestedThisRecording {
            editRequestedThisRecording = true
            onEditRequested?()
        }
        handleFnStateChange(isActive: fnActive)
    }

    private func handleFnStateChange(isActive fnActive: Bool) {
        switch state {
        case .idle:
            if fnActive {
                beginFirstPress()
            }

        case .firstPressDown:
            if !fnActive {
                beginSecondPressWindow()
            }

        case .waitingForSecondPress:
            if fnActive {
                beginSecondPressHold()
            }

        case .secondPressHolding:
            if !fnActive {
                resetState()
            }

        case .recording:
            if !fnActive {
                finishRecording()
            }
        }
    }

    private func beginFirstPress() {
        state = .firstPressDown
        scheduleTimer(after: Self.secondHoldThreshold) { [weak self] in
            guard let self, self.state == .firstPressDown else { return }
            self.resetState()
        }
    }

    private func beginSecondPressWindow() {
        state = .waitingForSecondPress
        scheduleTimer(after: Self.doubleTapWindow) { [weak self] in
            guard let self, self.state == .waitingForSecondPress else { return }
            self.resetState()
        }
    }

    private func beginSecondPressHold() {
        state = .secondPressHolding
        scheduleTimer(after: Self.secondHoldThreshold) { [weak self] in
            guard let self, self.state == .secondPressHolding else { return }
            self.state = .recording
            self.editRequestedThisRecording = false
            self.invalidateTimer()
            self.onRecordingStart?()
        }
    }

    private func finishRecording() {
        state = .idle
        invalidateTimer()
        onRecordingStop?()
    }

    private func resetState() {
        state = .idle
        invalidateTimer()
    }

    private func scheduleTimer(after interval: TimeInterval, handler: @escaping () -> Void) {
        invalidateTimer()
        let timer = Timer(timeInterval: interval, repeats: false) { _ in
            handler()
        }
        stateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func invalidateTimer() {
        stateTimer?.invalidate()
        stateTimer = nil
    }
}
